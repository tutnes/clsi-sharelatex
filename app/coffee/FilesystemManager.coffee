child_process = require("child_process")
logger = require "logger-sharelatex"
settings = require "settings-sharelatex"
Path = require "path"
wrench = require "wrench"
mkdirp = require "mkdirp"
fs = require "fs"
async = require "async"

module.exports = FilesystemManager =
			
	initProject: (project_id, callback = (error) ->) ->
		directory = Path.join(settings.path.compilesDir, project_id)
		mkdirp directory, callback
			
	_getNormalizedPath: (project_id, filePath, callback = (error, path) ->) ->
		basePath = Path.join(settings.path.compilesDir, project_id)
		path = Path.normalize(Path.join(basePath, filePath))
		if (path.slice(0, basePath.length) != basePath)
			return callback new Error("resource path is outside root directory")
		callback null, path
			
	deleteFileIfNotDirectory: (project_id, filePath, callback = (error) ->) ->
		FilesystemManager._getNormalizedPath project_id, filePath, (error, path) ->
			return callback(error) if error?
			fs.stat path, (error, stat) ->
				return callback(error) if error?
				if stat.isFile()
					fs.unlink path, callback
				else
					callback()
		
	addFiles: (project_id, files, callback = (error) ->) ->
		async.eachSeries files,
			(file, callback) ->
				if file.content?
					FilesystemManager._addFileFromContent project_id, file.path, file.content, callback
				else if file.src?
					FilesystemManager._addFileFromStream project_id, file.path, fs.createReadStream(file.src), callback
			callback
		
	_addFileFromStream: (project_id, filePath, readStream, callback = (error) ->) ->
		callbackOnce = (error) ->
			callback(error)
			callback = () ->

		readStream.on "error", callbackOnce
		FilesystemManager._getNormalizedPath project_id, filePath, (error, path) ->
			return callback(error) if error?
			mkdirp Path.dirname(path), (error) ->
				return callback(error) if error?
				fs.unlink path, (error) -> # unlink the file if it exists, ignore errors
					writeStream = fs.createWriteStream(path, {mode: 0o444})
					writeStream.on "error", callbackOnce
					writeStream.on "close", () -> callbackOnce()
					readStream.pipe(writeStream)
			
	_addFileFromContent: (project_id, filePath, content, callback = (error) ->) ->
		FilesystemManager._getNormalizedPath project_id, filePath, (error, path) ->
			return callback(error) if error?
			mkdirp Path.dirname(path), (error) ->
				return callback(error) if error?
				fs.unlink path, (error) ->
					fs.writeFile path, content, {mode: 0o444}, callback
			
	clearProject: (project_id, _callback = (error) ->) -> 
		callback = (error) ->
			_callback(error)
			_callback = () ->

		directory = Path.join(settings.path.compilesDir, project_id)
		logger.log {directory}, "running rm -r in clearProject"
		proc = child_process.spawn "rm", ["-r", directory]

		proc.on "error", callback

		stderr = ""
		proc.stderr.on "data", (chunk) -> stderr += chunk.toString()

		proc.on "close", (code) ->
			if code == 0
				return callback(null)
			else
				return callback(new Error("rm -r #{directory} failed: #{stderr}"))

	deleteEmptyDirectories: (project_id, _callback = (error) ->) ->
		callback = (error) ->
			_callback(error)
			_callback = () ->

		directory = Path.join(settings.path.compilesDir, project_id)
		args = [directory,
			"-depth", "-mindepth", "1",
			"-type", "d",
			"-gid", process.getgid() # delete empty directories owned by the editor
			"-empty", "-delete" ]
		logger.log args: args, "running find command in deleteEmptyDirectories"
		proc = child_process.spawn "find", args

		proc.on "error", callback

		stderr = ""
		proc.stderr.on "data", (chunk) -> stderr += chunk.toString()

		proc.on "close", (code) ->
			if code == 0
				return callback(null)
			else
				return callback(new Error("find/-delete #{directory} failed: #{stderr}"))

	getAllFiles: (project_id, options, _callback) ->
		if not _callback?
			if typeof options == "function"
				_callback = options
				options = {}
			else
				_callback = (error, files) ->

		callback = (error, fileList) ->
			_callback(error, fileList)
			_callback = () ->
				
		directory = Path.join(settings.path.compilesDir, project_id)
		args = [directory, "-type", "f"]
		if options?.gid?
			args.push "-gid", options.gid
		if options?.group?
			args.push "-group", options.group
		logger.log args: args, "running find command in getAllFiles"

		proc = child_process.spawn("find", args)
		stdout = ""
		proc.stdout.on "data", (chunk) ->
			stdout += chunk.toString()	
		proc.on "error", callback	
		proc.on "close", (code) ->
			if code != 0
				logger.warn {directory, code}, "find returned error, directory likely doesn't exist"
				return callback null, []
			fileList = stdout.split("\n").filter (file) -> file != ""
			fileList = fileList.map (file) ->
				# Strip leading directory
				if file.slice(0, directory.length) == directory
					return Path.relative(directory, file)
				else
					return file
			return callback null, fileList

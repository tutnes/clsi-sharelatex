async = require "async"
fs = require "fs"
Path = require "path"
spawn = require("child_process").spawn
logger = require "logger-sharelatex"
glob = require("glob")

module.exports = OutputFileFinder =
	findOutputFiles: (resources, directory, callback = (error, outputFiles) ->) ->
		incomingResources = {}
		for resource in resources
			incomingResources[resource.path] = true
			
		logger.log directory: directory, "getting output files"

		OutputFileFinder._getAllFiles directory, (error, allFiles = []) ->
			return callback(error) if error?
			jobs = []
			outputFiles = []
			for file in allFiles
				if !incomingResources[file]
					outputFiles.push {
						path: file
						type: file.match(/\.([^\.]+)$/)?[1]
					}
			callback null, outputFiles

	_getAllFiles: (directory, callback = (error, fileList) ->) ->
		# the original command was find -name .cache -prune -o -type f -print
		#
		# the glob command below has one difference: it ignores all dot
		# files and directories (.*).  If the user is not creating dot files then it should be ok.
		glob "**/*", { cwd: directory, dot:false, nonull:false, nodir:true, follow:false}, (err, result) ->
			console.log 'GLOB:', err, result
			callback(err, result)

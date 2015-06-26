UrlCache = require "./UrlCache"
Path = require "path"
fs = require "fs"
async = require "async"
OutputFileFinder = require "./OutputFileFinder"
Metrics = require "./Metrics"
FilesystemManager = require "./FilesystemManager"
_ = require "underscore"
logger = require "logger-sharelatex"
LRU = require "lru-cache"

FileListCache = LRU(1024)

module.exports = ResourceWriter =
	syncResourcesToDisk: (project_id, resources, callback = (error) ->) ->
		@_removeExtraneousFiles project_id, resources, (error) =>
			return callback(error) if error?
			@_writeResourcesToDisk(project_id, resources, callback)

	_removeExtraneousFiles: (project_id, resources, _callback = (error) ->) ->
		timer = new Metrics.Timer("unlink-output-files")
		callback = (error) ->
			timer.done()
			_callback(error)

		# do we have a cached list of resources?
		# if so, delete the ones not in the list any more
		# and delete any directories which are now empty because those files were removed

		@_findPreviousFiles project_id, (error, oldFilesList) =>
			logger.log {oldFilesList}, "old files"
			@_findCurrentFiles project_id, resources, (error, newFilesList) ->
				removedFilesList = _.difference oldFilesList, newFilesList
				logger.log {removedFilesList}, "files to remove"
				jobs = []
				for file in removedFilesList or []
					do (file) ->
						jobs.push (callback) ->
							FilesystemManager.deleteFileIfNotDirectory project_id, file, callback

				async.series jobs, (error) ->
					return callback(error) if error?
					FilesystemManager.deleteEmptyDirectories project_id, callback

	_findPreviousFiles: (project_id, callback = (error, result) ->) ->
		prevFiles = FileListCache.get project_id
		if prevFiles?
			logger.log {prevFiles}, "old files"
			callback null, prevFiles
		else
			FilesystemManager.getAllFiles project_id, {gid: process.getgid()}, callback

	_findCurrentFiles: (project_id, resources, callback = (error, result) ->) ->
		newFiles = {}
		for resource in resources
			newFiles[resource.path] = true
		newFilesList = _.keys newFiles
		logger.log {newFilesList}, "new files"
		FileListCache.set project_id, newFilesList
		callback null, newFilesList

	_writeResourcesToDisk: (project_id, resources, callback = (error) ->) ->
		async.mapSeries resources,
			(resource, callback) ->
				if resource.url?
					UrlCache.getPathOnDisk project_id, resource.url, resource.modified, (error, pathOnDisk) ->
						return callback(error) if error?
						callback null, {
							path: resource.path
							src:  pathOnDisk
						}
				else
					callback null, {
						path:    resource.path
						content: resource.content
					}
			(error, files) ->
				return callback(error) if error?
				FilesystemManager.addFiles project_id, files, callback



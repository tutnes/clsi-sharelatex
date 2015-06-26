SandboxedModule = require('sandboxed-module')
sinon = require('sinon')
require('chai').should()
modulePath = require('path').join __dirname, '../../../app/js/ResourceWriter'
path = require "path"

describe "ResourceWriter", ->
	beforeEach ->
		@ResourceWriter = SandboxedModule.require modulePath, requires:
			"fs": @fs = {}
			"wrench": @wrench = {}
			"./UrlCache" : @UrlCache = {}
			"mkdirp" : @mkdirp = sinon.stub().callsArg(1)
			"./OutputFileFinder": @OutputFileFinder = {}
			"./Metrics": @Metrics =
				Timer: class Timer
					done: sinon.stub()
			"./FilesystemManager": @FilesystemManager = {}
			"logger-sharelatex": @logger = { log: sinon.stub(), error: sinon.stub() }
		@project_id = "project-id-123"
		@callback = sinon.stub()

	describe "syncResourcesToDisk", ->
		beforeEach ->
			@resources = [
				"resource-1-mock"
				"resource-2-mock"
				"resource-3-mock"
			]
			@ResourceWriter._writeResourcesToDisk = sinon.stub().callsArg(2)
			@ResourceWriter._removeExtraneousFiles = sinon.stub().callsArg(2)
			@ResourceWriter.syncResourcesToDisk(@project_id, @resources, @callback)

		it "should remove old files", ->
			@ResourceWriter._removeExtraneousFiles
				.calledWith(@project_id, @resources)
				.should.equal true

		it "should write the resources to disk", ->
			@ResourceWriter._writeResourcesToDisk
				.calledWith(@project_id, @resources)
				.should.equal true

		it "should call the callback", ->
			@callback.called.should.equal true

	describe "_removeExtraneousFiles", ->
		beforeEach ->
			@previous_files = ['test.py', 'test.R']
			@current_files = ['test.R']
			@resources = [{
				path: "test.R"
				type: "txt"
			}]
			@ResourceWriter._findPreviousFiles = sinon.stub().callsArgWith(1, null, @previous_files)
			@ResourceWriter._findCurrentFiles = sinon.stub().callsArgWith(2, null, @current_files)
			@FilesystemManager.deleteFileIfNotDirectory = sinon.stub().callsArg(2)
			@FilesystemManager.deleteEmptyDirectories = sinon.stub().callsArg(1)
			@ResourceWriter._removeExtraneousFiles(@project_id, @resources, @callback)

		it "should find the existing files", ->
			@ResourceWriter._findPreviousFiles
				.calledWith(@project_id)
				.should.equal true

		it "should find the new files", ->
			@ResourceWriter._findCurrentFiles
				.calledWith(@project_id, @resources)
				.should.equal true

		it "should unlink the deleted files", ->
			@FilesystemManager.deleteFileIfNotDirectory
				.calledWith(@project_id, "test.py")
				.should.equal true

		it "should delete any empty directories", ->
			@FilesystemManager.deleteEmptyDirectories
				.calledWith(@project_id)
				.should.equal true

		it "should call the callback", ->
			@callback.called.should.equal true

		it "should time the request", ->
			@Metrics.Timer::done.called.should.equal true

	describe "_writeResourcesToDisk", ->
		describe "with a url based resource", ->
			beforeEach ->
				@resources = [
					path: "main.tex"
					url: "http://www.example.com/main.tex"
					modified: Date.now()
				]
				@UrlCache.getPathOnDisk = sinon.stub().callsArgWith(3, null, @pathOnDisk = "/path/on/disk")
				@FilesystemManager.addFiles = sinon.stub().callsArg(2)
				@ResourceWriter._writeResourcesToDisk(@project_id, @resources, @callback)

			it "should get the URL from the cache", ->
				@UrlCache.getPathOnDisk
					.calledWith(@project_id, @resources[0].url, @resources[0].modified)
					.should.equal true
					
			it "should add the file to the command runner", ->
				@FilesystemManager.addFiles
					.calledWith(@project_id, [{
						path: "main.tex"
						src:  @pathOnDisk
					}])
					.should.equal true
			
			it "should call the callback", ->
				@callback.called.should.equal true

		describe "with a content based resource", ->
			beforeEach ->
				@resources = [
					path: "main.tex"
					content: "Hello world"
				]
				@FilesystemManager.addFiles = sinon.stub().callsArg(2)
				@ResourceWriter._writeResourcesToDisk(@project_id, @resources, @callback)

			it "should add the file to the command runner", ->
				@FilesystemManager.addFiles
					.calledWith(@project_id, [{
						path: @resources[0].path
						content: @resources[0].content
					}])
					.should.equal true
				
			it "should call the callback", ->
				@callback.called.should.equal true


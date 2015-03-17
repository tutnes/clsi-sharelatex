SandboxedModule = require('sandboxed-module')
sinon = require('sinon')
require('chai').should()
modulePath = require('path').join __dirname, '../../../app/js/OutputFileFinder'
path = require "path"
expect = require("chai").expect
EventEmitter = require("events").EventEmitter
mock = require("mock-fs")

describe "OutputFileFinder", ->
	beforeEach ->
		@OutputFileFinder = SandboxedModule.require modulePath, requires:
			"logger-sharelatex": { log: sinon.stub(), warn: sinon.stub() }
		@directory = "/test/dir"
		@callback = sinon.stub()

	describe "findOutputFiles", ->
		beforeEach ->
			@resource_path = "resource/path.tex"
			@output_paths   = ["output.pdf", "extra/file.tex"]
			@all_paths = @output_paths.concat [@resource_path]
			@resources = [
				path: @resource_path = "resource/path.tex"
			]
			@OutputFileFinder._getAllFiles = sinon.stub().callsArgWith(1, null, @all_paths)
			@OutputFileFinder.findOutputFiles @resources, @directory, (error, @outputFiles) =>

		it "should only return the output files, not directories or resource paths", ->
			expect(@outputFiles).to.deep.equal [{
				path: "output.pdf"
				type: "pdf"
			}, {
				path: "extra/file.tex",
				type: "tex"
			}]
			
	describe "_getAllFiles", ->
		beforeEach ->
			mock {
				'/base/dir' :
					'main.tex' : "hello world"
					'chapters' : {
						'chapter1.tex': "hello chapter 1"
					}
					'.cache' : {
						"123456" : {
							"output.log" : "old output"
							"output.pdf" : "old pdf"
						}
					}
			}

		afterEach ->
			mock.restore()

		describe "successfully", ->
			beforeEach (done) ->
				@directory = "/base/dir"
				@OutputFileFinder._getAllFiles @directory, (err,res) =>
					console.log 'ERR', err, 'RES', res
					@callback(err,res)
					done()

			it "should call the callback with the relative file paths", ->
				@callback.calledWith(
					null,
					["chapters/chapter1.tex", "main.tex"]
				).should.equal true

		describe "when the directory doesn't exist", ->
			beforeEach (done) ->
				@directory = "/base/doesntexist"
				@OutputFileFinder._getAllFiles @directory, (err,res) =>
					console.log 'ERR', err, 'RES', res
					@callback(err,res)
					done()
			
			it "should call the callback with a blank array", ->
				@callback.calledWith(
					null,
					[]
				).should.equal true

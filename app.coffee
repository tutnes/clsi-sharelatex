CompileController = require "./app/js/CompileController"
Settings = require "settings-sharelatex"
logger = require "logger-sharelatex"
ClsiLogger = logger.initialize("clsi").logger
ContentTypeMapper = require "./app/js/ContentTypeMapper"

if Settings.sentry?.dsn?
	logger.initializeErrorReporting(Settings.sentry.dsn)

# truncate long output messages in log
ClsiLogger.addSerializers {
	message: (msg) ->
		JSON.stringify msg, (key, value) ->
			if typeof value == 'string' && (len = value.length) > 255
				return value.substr(0,64) + "...(message of length #{len} truncated)"
			else
				return value
}

smokeTest = require "smoke-test-sharelatex"

Path = require "path"

Metrics = require "metrics-sharelatex"
Metrics.initialize("clsi")
Metrics.open_sockets.monitor(logger)

ProjectPersistenceManager = require "./app/js/ProjectPersistenceManager"

require("./app/js/db").sync()

express = require "express"
bodyParser = require "body-parser"
app = express()

app.use Metrics.http.monitor(logger)

# Compile requests can take longer than the default two
# minutes (including file download time), so bump up the
# timeout a bit.
TIMEOUT = 6 * 60 * 1000
app.use (req, res, next) ->
	req.setTimeout TIMEOUT
	res.setTimeout TIMEOUT
	next()

app.post   "/project/:project_id/compile", bodyParser.json(limit: "5mb"), CompileController.compile
app.post   "/project/:project_id/compile/:session_id/stop", CompileController.stopCompile
app.delete "/project/:project_id", CompileController.clearCache

app.post "/project/:project_id/request", bodyParser.json(limit: "5mb"), CompileController.sendJupyterRequest
app.post "/project/:project_id/reply", bodyParser.json(limit: "5mb"), CompileController.sendJupyterReply
app.post "/project/:project_id/request/:request_id/interrupt", CompileController.interruptJupyterRequest

app.delete '/project/:project_id/output/:file(\\S+)', CompileController.deleteFile
app.get "/project/:project_id/output", CompileController.listFiles

app.get  "/project/:project_id/sync/code", CompileController.syncFromCode
app.get  "/project/:project_id/sync/pdf", CompileController.syncFromPdf

app.get "/oops", (req, res, next) ->
	return next(new Error("test error"))

ForbidSymlinks = require "./app/js/StaticServerForbidSymlinks"

# create a static server which does not allow access to any symlinks
# avoids possible mismatch of root directory between middleware check
# and serving the files.
staticServer = ForbidSymlinks express.static, Settings.path.compilesDir, setHeaders: (res, path, stat) ->
	res.set("Content-Type", ContentTypeMapper.map(path))

app.get "/project/:project_id/output/*", (req, res, next) ->
	req.url = "/#{req.params.project_id}/#{req.params[0]}"
	staticServer(req, res, next)

app.get "/status", (req, res, next) ->
	res.send "CLSI is alive\n"

resCacher =
	contentType:(@setContentType)->
	send:(@code, @body)->

	#default the server to be down
	code:500
	body:{}
	setContentType:"application/json"

if Settings.smokeTest
	do runSmokeTest = ->
		logger.log("running smoke tests")
		smokeTest.run(require.resolve(__dirname + "/test/smoke/js/SmokeTests.js"))({}, resCacher)
		setTimeout(runSmokeTest, 20 * 1000)

app.get "/health_check", (req, res)->
	res.contentType(resCacher?.setContentType)
	res.status(resCacher?.code).send(resCacher?.body)

profiler = require "v8-profiler"
app.get "/profile", (req, res) ->
	time = parseInt(req.query.time || "1000")
	profiler.startProfiling("test")
	setTimeout () ->
		profile = profiler.stopProfiling("test")
		res.json(profile)
	, time

app.get "/heapdump", (req, res)->
	require('heapdump').writeSnapshot '/tmp/' + Date.now() + '.clsi.heapsnapshot', (err, filename)->
		res.send filename

app.use (error, req, res, next) ->
	logger.error err: error, "server error"
	res.sendStatus(error?.statusCode || 500)

app.listen port = (Settings.internal?.clsi?.port or 3013), host = (Settings.internal?.clsi?.host or "localhost"), (error) ->
	logger.info "CLSI starting up, listening on #{host}:#{port}"

setInterval () ->
	ProjectPersistenceManager.clearExpiredProjects()
, Settings.clsi?.checkProjectsIntervalMs or 10 * 60 * 1000 # 10 mins

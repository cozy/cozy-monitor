async = require "async"
fs = require "fs"
axon = require 'axon'
spawn = require('child_process').spawn
path = require('path')
log = require('printit')()
request = require("request-json-light")

helpers = require './helpers'
homeClient = helpers.clients.home
proxyClient = helpers.clients.proxy
dsClient = helpers.clients.ds
client = helpers.clients.controller
handleError = helpers.handleError
makeError = helpers.makeError
getToken = helpers.getToken

# Applications helpers #

waitInstallComplete = (slug, callback) ->
    axon   = require 'axon'
    socket = axon.socket 'sub-emitter'
    socket.connect 9105
    noAppListErrMsg = """
No application listed after installation.
"""
    appNotStartedErrMsg = """
Application is not running after installation.
"""
    appNotListedErrMsg = """
Expected application not listed in database after installation.
"""

    timeoutId = setTimeout ->
        socket.close()

        homeClient.get "api/applications/", (err, res, apps) ->
            if not apps?.rows?
                callback new Error noAppListErrMsg
            else
                isApp = false

                for app in apps.rows

                    if app.slug is slug and \
                       app.state is 'installed' and \
                       app.port

                        isApp = true
                        statusClient = request.newClient url
                        statusClient.host = "http://localhost:#{app.port}/"
                        statusClient.get "", (err, res) ->
                            if res?.statusCode in [200, 403]
                                callback null, state: 'installed'
                            else
                                callback new Error appNotStartedErrMsg

                unless isApp
                    callback new Error appNotListedErrMsg
    , 240000

    socket.on 'application.update', (id) ->
        clearTimeout timeoutId
        socket.close()

        dsClient.setBasicAuth 'home', token if token = getToken()
        dsClient.get "data/#{id}/", (err, response, body) ->
            if response.statusCode is 401
                dsClient.setBasicAuth 'home', ''
                dsClient.get "data/#{id}/", (err, response, body) ->
                    callback err, body
            else
                callback err, body


msgHomeNotStarted = (app) ->
    return """
Install home failed for #{app}.
The Cozy Home looks not started. Install operation cannot be performed.
"""
msgRepoGit = (app) ->
    return """
Install home failed for #{app}.
Default git repo #{manifest.git} doesn't exist.
You can use option -r to use a specific repo."""
msgLongInstall = (app) ->
    return """
#{app} installation is still running. You should check for its status later.
If the installation is too long, you should try to stop it by uninstalling the
application and running the installation again.
"""
msgInstallFailed = (app) ->
    return """
Install home failed. Can't figure out the app state.
"""

manifest =
   "domain": "localhost"
   "repository":
       "type": "git"
   "scripts":
       "start": "server.coffee"


# Applications functions #

# Callback all application stored in database
module.exports.getApps = (callback) ->
    homeClient.get "api/applications/", (err, res, apps) ->
        funcs = []
        if apps? and apps.rows?
            callback null, apps.rows
        else
            callback makeError(err, apps)


# Install application <app>
install = module.exports.install = (app, options, callback) ->
    # Create manifest
    manifest.name = app
    if options.displayName?
        manifest.displayName = options.displayName
    else
        manifest.displayName = app
    manifest.user = app

    unless options.repo?
        manifest.git =
            "https://github.com/cozy/cozy-#{app}.git"
    else
        manifest.git = options.repo

    if options.branch?
        manifest.branch = options.branch
    path = "api/applications/install"
    homeClient.headers['content-type'] = 'application/json'
    homeClient.post path, manifest, (err, res, body) ->
        if err or body.error
            if err?.code is 'ECONNREFUSED'
                err = makeError msgHomeNotStarted(app), null
            else if body?.message?.indexOf('Not Found') isnt -1
                console.log body.message
                err = makeError msgRepoGit(app), null
            else
                err = makeError err, body
            callback err
        else
            waitInstallComplete body.app.slug, (err, appresult) ->
                if err
                    callback makeError(err, null)
                else if appresult.state is 'installed'
                    log.info "#{app} was successfully installed."
                else if appresult.state is 'installing'
                    log.info msgLongInstall(app)
                else
                    callback makeError(msgFailed(app), null)


# Uninstall application <app>
uninstall = module.exports.uninstall = (app, callback) ->
    path = "api/applications/#{app}/uninstall"
    homeClient.del path, (err, res, body) ->
        if err or body.error
            callback makeError(err, body)
        else
            callback()


# Start application <app>
start = module.exports.start = (app, callback) ->
    find = false
    homeClient.get "api/applications/", (err, res, apps) ->
        if apps? and apps.rows?
            for manifest in apps.rows when manifest.name is app
                find = true
                path = "api/applications/#{manifest.slug}/start"
                homeClient.post path, manifest, (err, res, body) ->
                    if err or body.error
                        callback makeError(err, body)
                    else
                        callback()
            unless find
                msg= "application #{app} not found."
                callback makeError(msg)
        else
            msg = "no applications installed."
            callback makeError(msg)


# Stop application <app>
stop = module.exports.stop = (app, callback) ->
    find = false
    homeClient.get "api/applications/", (err, res, apps) ->
        if apps?.rows?
            for manifest in apps.rows when manifest.name is app
                find = true
                path = "api/applications/#{app}/stop"
                homeClient.post path, app, (err, res, body) ->
                    if err? or body.error?
                        callback makeError(err, body)
                    else
                        callback()
            unless find
                err = "application #{app} not found"
                callback makeError(err, null)
        else
            err = "application #{app} not found"
            callback makeError(err, null)


# Update application <app>
module.exports.update = (app, repo=null, callback) ->
    find = false
    homeClient.get "api/applications/", (err, res, apps) ->
        if apps? and apps.rows?
            for manifest in apps.rows
                if manifest.name is app
                    find = true
                    path = "api/applications/#{manifest.slug}/update"
                    homeClient.put path, manifest, (err, res, body) ->
                        if err or body.error
                            callback makeError(err, body)
                        else
                            callback()
            if not find
                err = "Update failed: #{app} was not found."
                callback makeError(err, null)
        else
            err = "Update failed: no application installed"
            callback makeError(err, null)


# Restart application <app>
module.exports.restart = (app, callback) ->
    log.info "stop #{app}"
    stop app, (err) ->
        if err
            callback err
        else
            log.info "start #{app}"
            start app, callback


# Restop (start and stop) application <app>
module.exports.restop = (app, callback) ->
    log.info "start #{app}"
    start app, (err) ->
        if err
            callback err
        else
            log.info "stop #{app}"
            stop app, callback


# Reinstall application <app>
module.exports.reinstall = (app, options, callback) ->
    log.info "uninstall #{app}"
    uninstall app, (err) ->
        if err
            callback err
        else
            log.info "install #{app}"
            install app, options, callback


# Put autostoppable application <app>
module.exports.autoStop = (app, callback) ->
    unStoppable = ['pfm', 'emails', 'feeds', 'nirc', 'sync', 'konnectors']
    if not(app.name in unStoppable) and not app.isStoppable
        app.isStoppable = true
        homeClient.put "api/applications/byid/#{app.id}", app, (err, res, body) ->
            if err? or body.error
                callback makeError(err, body)
            else
                callback()
    else
        callback()


# Callback application version
module.exports.getVersion = (app, callback) ->
    callback app.version


# Callback application state
module.exports.check = (app, url) ->
    (callback) ->
        statusClient = request.newClient url
        url.get "", (err, res) ->
            if (res? and not res.statusCode in [200,403]) or (err? and
                err.code is 'ECONNREFUSED')
                    log.raw "#{app}: " + "down".red
            else
                log.raw "#{app}: " + "up".green
            callback()
        , false


## Usefull for application developpement


# Generate a random 32 char string.
randomString = (length=32) ->
    string = ""
    string += Math.random().toString(36).substr(2) while string.length < length
    string.substr 0, length

removeApp = (apps, name, callback) ->
    if apps.length > 0
        app = apps.pop().value
        if app.name is name
            console.log app._id
            dsClient.del "data/#{app._id}/", (err, response, body) ->
                removeApp apps, name, callback
        else
            removeApp apps, name, callback
    else
        callback()

## Start applicationn without controller in a production environment.
# * Add/Replace application in database (for home and proxy)
# * Reset proxy
# * Start application with environment variable
# * When application is stopped : remove application in database and reset proxy
module.exports.startStandalone = (port, callback) ->
    recoverManifest = (cb) ->
        unless fs.existsSync 'package.json'
            log.error "Cannot read package.json. " +
                "This function should be called in root application folder."
        else
            try
                packagePath = path.relative __dirname, 'package.json'
                manifest = require packagePath
            catch err
                log.raw err
                log.error "Package.json isn't correctly formatted."
                return

            # Retrieve manifest from package.json
            manifest.name = "#{manifest.name}test"
            manifest.permissions = manifest['cozy-permissions']
            manifest.displayName =
                manifest['cozy-displayName'] or manifest.name
            manifest.state = "installed"
            manifest.password = randomString()
            manifest.docType = "Application"
            manifest.port = port
            manifest.slug = manifest.name.replace 'cozy-', ''

            if manifest.slug in ['hometest', 'proxytest', 'data-systemtest']
                log.error(
                    'Sorry, cannot start stack application without ' +
                    ' controller.')
                cb()
            else
                cb(manifest)


    putInDatabase = (manifest, cb) ->
        log.info "Add/replace application in database..."
        token = getToken()
        if token?
            dsClient.setBasicAuth 'home', token
            requestPath = "request/application/all/"
            dsClient.post requestPath, {}, (err, response, apps) ->
                if err
                    log.error "Data-system looks down (not responding)."
                else
                    removeApp apps, manifest.name, () ->
                        dsClient.post "data/", manifest, (err, res, body) ->
                            id = body._id
                            if err
                                log.error "Cannot add application in database."
                                cb makeError(err, body)
                            else
                                cb()

    id = 0
    process.on 'SIGINT', ->
        stopStandalone (err) ->
            if not err?
                console.log "Application removed"
        , manifest
    process.on 'uncaughtException', (err) ->
        log.error 'uncaughtException'
        log.raw err
        removeFromDatabase()
    log.info "Retrieve application manifest..."
    # Recover application manifest
    recoverManifest (manifest) ->
        # Add/Replace application in database
        putInDatabase manifest, (err) ->
            return callback err if err?
            # Reset proxy
            log.info "Reset proxy..."
            proxyClient.get "routes/reset", (err, res, body) ->
                if err
                    log.error "Cannot reset routes."
                    return callback makeError(err, body)
                else
                    # Add environment varaible.
                    log.info "Start application..."
                    process.env.TOKEN = manifest.password
                    process.env.NAME = manifest.slug
                    process.env.NODE_ENV = "production"

                    # Start application
                    server = spawn "npm",  ["start"]
                    server.stdout.setEncoding 'utf8'
                    server.stdout.on 'data', (data) ->
                        log.raw data

                    server.stderr.setEncoding 'utf8'
                    server.stderr.on 'data', (data) ->
                        log.raw data
                    server.on 'error', (err) ->
                        log.raw err
                    server.on 'close', (code) ->
                        log.info "Process exited with code #{code}"


## Stop applicationn without controller in a production environment.
# * Remove application in database and reset proxy
# * Usefull if start-standalone doesn't remove app
stopStandalone = module.exports.stopStandalone = (callback, manifest=null) ->

    log.info "Retrieve application manifest ..."
    if not manifest
        # Recover application manifest
        unless fs.existsSync 'package.json'
            error = "Cannot read package.json. " +
                "This function should be called in root application  folder"
            return callback makeError(err, null)
        try
            packagePath = path.relative __dirname, 'package.json'
            manifest = require packagePath
        catch err
            error "Package.json isn't in a correct format"
            return callback makeError(err, null)
        # Retrieve manifest from package.json
        manifest.name = manifest.name + "test"
        manifest.slug = manifest.name.replace 'cozy-', ''
    if manifest.slug in ['hometest', 'proxytest', 'data-systemtest']
        error = 'Sorry, cannot start stack application without controller.'
        callback makeError(err, null)
    else
        # Add/Replace application in database
        token = getToken()
        unless token?
            return
        log.info "Remove from database ..."
        dsClient.setBasicAuth 'home', token
        requestPath = "request/application/all/"
        dsClient.post requestPath, {}, (err, response, apps) =>
            if err
                return callback makeError("Data-system doesn't respond", null)
            removeApp apps, manifest.name, () ->
                log.info "Reset proxy ..."
                proxyClient.get "routes/reset", (err, res, body) ->
                    if err
                        log.error "Cannot reset routes."
                        callback makeError(err, null)
                    else
                        callback()
require "colors"
program = require 'commander'
async = require "async"
fs = require "fs"
axon = require 'axon'
exec = require('child_process').exec
spawn = require('child_process').spawn
path = require('path')
log = require('printit')()
request = require("request-json-light")

helpers = require './helpers'
homeClient = helpers.homeClient
handleError = helpers.handleError


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

        statusClient.host = homeUrl
        statusClient.get "api/applications/", (err, res, apps) ->
            if not apps?.rows?
                callback new Error noAppListErrMsg
            else
                isApp = false

                for app in apps.rows

                    if app.slug is slug and \
                       app.state is 'installed' and \
                       app.port

                        isApp = true
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

        dSclient = request.newClient dataSystemUrl
        dSclient.setBasicAuth 'home', token if token = getToken()
        dSclient.get "data/#{id}/", (err, response, body) ->
            if response.statusCode is 401
                dSclient.setBasicAuth 'home', ''
                dSclient.get "data/#{id}/", (err, response, body) ->
                    callback err, body
            else
                callback err, body

startApp = (app, callback) ->
    path = "api/applications/#{app.slug}/start"
    homeClient.post path, app, (err, res, body) ->
        if err
            callback err
        else if body.error
            callback new Error body.error
        else
            callback()


removeApp = (app, callback) ->
    path = "api/applications/#{app.slug}/uninstall"
    homeClient.del path, (err, res, body) ->
        if err
            callback err, body
        else if body.error
            callback new Error body.error, body
        else
            callback()
                callback null


installApp = (app, callback) ->
    manifest =
        "domain": "localhost"
        "repository":
            "type": "git"
        "scripts":
            "start": "server.coffee"
        "name": app.name
        "displayName":  app.displayName
        "user": app.name
        "git": app.git
    if app.branch?
        manifest.repository.branch = app.branch
    path = "api/applications/install"
    homeClient.headers['content-type'] = 'application/json'
    homeClient.post path, manifest, (err, res, body) ->
        if err
            callback err
        else if body?.error
            callback new Error body.error
        else
            waitInstallComplete app.slug, (err, appresult) ->
                if err
                    callback err
                else
                    callback()


stopApp = (app, callback) ->
    path = "api/applications/#{app.slug}/stop"
    homeClient.post path, app, (err, res, body) ->
        if err
            callback err
        else if body.error
            callback new Error body.error
        else
            callback()


manifest =
   "domain": "localhost"
   "repository":
       "type": "git"
   "scripts":
       "start": "server.coffee"

module.exports.install = (app, options, callback) ->
    # Create manifest
    manifest.name = app
    if options.displayName?
        manifest.displayName = options.displayName
    else
        manifest.displayName = app
    manifest.user = app

    log.info "Install started for #{app}..."

    unless options.repo?
        manifest.git =
            "https://github.com/cozy/cozy-#{app}.git"
    else
        manifest.git = options.repo

    if options.branch?
        manifest.branch = options.branch
    path = "api/applications/install"
    homeClient.post path, manifest, (err, res, body) ->
        if err or body.error
            if err?.code is 'ECONNREFUSED'
                msg = """
Install home failed for #{app}.
The Cozy Home looks not started. Install operation cannot be performed.
"""
                handleError err, body, msg
            else if body?.message?.indexOf('Not Found') isnt -1
                msg = """
Install home failed for #{app}.
Default git repo #{manifest.git} doesn't exist.
You can use option -r to use a specific repo."""
                handleError err, body, msg
            else
                handleError err, body, "Install home failed for #{app}."

        else
            waitInstallComplete body.app.slug, (err, appresult) ->
                if err
                    msg = "Install home failed."
                    handleError err, null, msg
                else if appresult.state is 'installed'
                    log.info "#{app} was successfully installed."
                else if appresult.state is 'installing'
                    log.info """
#{app} installation is still running. You should check for its status later.
If the installation is too long, you should try to stop it by uninstalling the
application and running the installation again.
"""
                else
                    msg = """
Install home failed. Can't figure out the app state.
"""
                    handleError err, null, msg




# Uninstall
module.exports.uninstall = (app, callback) ->
    log.info "Uninstall started for #{app}..."
    removeApp "slug": app, (err, body)->
        if err
            handleError err, body, "Uninstall home failed for #{app}."
        else
            log.info "#{app} was successfully uninstalled."


# Start
module.exports.start = (app, callback) ->
    log.info "Starting #{app}..."
    find = false
    homeClient.host = homeUrl
    homeClient.get "api/applications/", (err, res, apps) ->
        if apps? and apps.rows?
            for manifest in apps.rows when manifest.name is app
                find = true
                startApp manifest, (err) ->
                    if err
                        handleError err, null, "Start failed for #{app}."
                    else
                        log.info "#{app} was successfully started."
            unless find
                log.error "Start failed : application #{app} not found."
        else
            log.error "Start failed : no applications installed."


# Stop
module.exports.stop = (app, callback) ->
    log.info "Stopping #{app}..."
    find = false
    homeClient.host = homeUrl
    homeClient.get "api/applications/", (err, res, apps) ->
        if apps?.rows?
            for manifest in apps.rows when manifest.name is app
                find = true
                stopApp manifest, (err) ->
                    if err
                        handleError err, null, "Stop failed for #{app}."
                    else
                        log.info "#{app} was successfully stopped."
            unless find
                log.error "Stop failed: application #{app} not found"
        else
            log.error "Stop failed: no applications installed."

# Restart
module.exports.restart = (app, callback) ->
    log.info "Stopping #{app}..."
    stopApp slug: app, (err) ->
        if err
            handleError err, null, "Stop failed"
        else
            log.info "#{app} successfully stopped"
            log.info "Starting #{app}..."
            startApp slug: app, (err) ->
                if err
                    handleError err, null, "Start failed for #{app}."
                else
                    log.info "#{app} was sucessfully started."



# Update
module.exports.update = (app, callback) ->
    log.info "Updating #{app}..."
    find = false
    homeClient.get "api/applications/", (err, res, apps) ->
        if apps? and apps.rows?
            for manifest in apps.rows
                if manifest.name is app
                    find = true
                    path = "api/applications/#{manifest.slug}/update"
                    homeClient.put path, manifest, (err, res, body) ->
                        if err or body.error
                            handleError err, body, "Update failed."
                        else
                            log.info "#{app} was successfully updated"
            if not find
                log.error "Update failed: #{app} was not found."
        else
            log.error "Update failed: no application installed"


module.exports.forceRestart = (callback) ->
        restart = (app, callback) ->
            # Start function in home restart application
            startApp app, (err) ->
                if err
                    log.error "Restart failed"
                else
                    log.info "... successfully"
                callback()

        restop = (app, callback) ->
            startApp app, (err) ->
                if err
                    log.error "Stop failed for #{app}."
                else
                    stopApp app, (err) ->
                        if err
                            log.error "Start failed for #{app}."
                        else
                            log.info "... successfully"
                            callback()

        reinstall = (app, callback) ->
            removeApp app, (err) ->
                if err
                    msg = "Uninstall failed for #{app}."
                else
                    installApp app, (err) ->
                        if err
                            msg = "Install failed for #{app}."
                        else
                            log.info "... successfully"
                            callback()

        homeClient.get "api/applications/", (err, res, apps) ->
            funcs = []
            if apps? and apps.rows?
                async.forEachSeries apps.rows, (app, callback) ->
                    switch app.state
                        when 'installed'
                            log.info "Restart #{app.slug}..."
                            restart app, callback
                        when 'stopped'
                            log.info "Restop #{app.slug}..."
                            restop app, callback
                        when 'installing'
                            log.info "Reinstall #{app.slug}..."
                            reinstall app, callback
                        when 'broken'
                            log.info "Reinstall #{app.slug}..."
                            reinstall app, callback
                        else
                            callback()


## Start applicationn without controller in a production environment.
# * Add/Replace application in database (for home and proxy)
# * Reset proxy
# * Start application with environment variable
# * When application is stopped : remove application in database and reset proxy
module.exports.startStandalone = (port, callback) ->
    id = 0
    # Remove from database when process exit.
    removeFromDatabase = ->
        log.info "Remove application from database ..."
        dsClient.del "data/#{id}/", (err, response, body) ->
            statusClient.host = proxyUrl
            statusClient.get "routes/reset", (err, res, body) ->
                if err
                    handleError err, body, "Cannot reset routes."
                else
                    log.info "Reset proxy succeeded."
    process.on 'SIGINT', ->
        removeFromDatabase()
    process.on 'uncaughtException', (err) ->
        log.error 'uncaughtException'
        log.raw err
        removeFromDatabase()

    recoverManifest = (callback) ->
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
            else
                callback(manifest)


    putInDatabase = (manifest, callback) ->
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
                                msg = "Cannot add application in database."
                                handleError err, body, msg
                            else
                                callback()


    removeApp = (apps, name, callback) ->
        if apps.length > 0
            app = apps.pop().value
            if app.name is name
                dsClient.del "data/#{app._id}/", (err, response, body) ->
                    removeApp apps, name, callback
            else
                removeApp apps, name, callback
        else
            callback()

    log.info "Retrieve application manifest..."
    # Recover application manifest
    recoverManifest (manifest) ->
        # Add/Replace application in database
        putInDatabase manifest, () ->
            # Reset proxy
            log.info "Reset proxy..."
            statusClient.host = proxyUrl
            statusClient.get "routes/reset", (err, res, body) ->
                if err
                    handleError err, body, "Cannot reset routes."
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
module.exports.stopStandalone = (callback) ->
    removeApp = (apps, name, callback) ->
        if apps.length > 0
            app = apps.pop().value
            if app.name is name
                dsClient.del "data/#{app._id}/", (err, response, body) =>
                    removeApp apps, name, callback
            else
                removeApp apps, name, callback
        else
            callback()

    log.info "Retrieve application manifest ..."
    # Recover application manifest
    unless fs.existsSync 'package.json'
        log.error "Cannot read package.json. " +
            "This function should be called in root application  folder"
        return
    try
        packagePath = path.relative __dirname, 'package.json'
        manifest = require packagePath
    catch err
        log.raw err
        log.error "Package.json isn't in a correct format"
        return
    # Retrieve manifest from package.json
    manifest.name = manifest.name + "test"
    manifest.slug = manifest.name.replace 'cozy-', ''
    if manifest.slug in ['hometest', 'proxytest', 'data-systemtest']
        log.error 'Sorry, cannot start stack application without controller.'
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
                log.error "Data-system doesn't respond"
                return
            removeApp apps, manifest.name, () ->
                log.info "Reset proxy ..."
                statusClient.host = proxyUrl
                statusClient.get "routes/reset", (err, res, body) ->
                    if err
                        handleError err, body, "Cannot reset routes."
                    else
                        log.info "Stop standalone finished with success"



module.exports.stopAll = (callback) ->
    stopApps = (app) ->
        (callback) ->
            log.info "\nStop #{app.name}..."
            stopApp app, (err) ->
                if err
                    log.error "\nStopping #{app.name} failed."
                    log.raw err
                callback()

    homeClient.host = homeUrl
    homeClient.get "api/applications/", (err, res, apps) ->
        funcs = []
        if apps? and apps.rows?
            for app in apps.rows
                func = stopApps(app)
                funcs.push func

            async.series funcs, ->
                log.info "\nAll apps stopped."
                log.info "Reset proxy routes"

                statusClient.host = proxyUrl
                statusClient.get "routes/reset", (err, res, body) ->
                    if err
                        handleError err, body, "Cannot reset routes."
                    else
                        log.info "Reset proxy succeeded."


module.exports.autoStopAll = (callback) ->
    unStoppable = ['pfm', 'emails', 'feeds', 'nirc', 'sync', 'konnectors']
    homeClient.host = homeUrl
    homeClient.get "api/applications/", (err, res, apps) ->
        if apps?.rows?
            for app in apps.rows
                if not(app.name in unStoppable) and not app.isStoppable
                    app.isStoppable = true
                    homeClient.put "api/applications/byid/#{app.id}",
                        app, (err, res) ->
                           log.error app.name
                           log.raw err

module.exports.updateAll = (callbacn) ->
    lightUpdateApp = (app, callback) ->
        path = "api/applications/#{app.slug}/update"
        homeClient.put path, app, (err, res, body) ->
            if err
                callback err
            else if body.error
                callback new Error body.error
            else
                callback()

    endUpdate = (app, callback) ->
        path = "api/applications/byid/#{app.id}"
        homeClient.get path, (err, res, app) ->
            if app.state is "installed"
                log.info " * New status: " + "started".bold
            else
                if app?.state?
                    log.info " * New status: " + app.state.bold
                else
                    log.info " * New status: unknown"
            log.info "#{app.name} updated"
            callback()

    updateApp = (app) ->
        (callback) ->
            log.info "\nStarting update #{app.name}..."
            # When application is broken, try :
            #   * remove application
            #   * install application
            #   * stop application
            switch app.state
                when 'broken'
                    log.info " * Old status: " + "broken".bold
                    log.info " * Remove #{app.name}"
                    removeApp app, (err, body) ->
                        if err
                            log.error 'An error occured: '
                            log.raw err
                            log.raw body

                        log.info " * Install #{app.name}"
                        installApp app, (err) ->
                            if err
                                log.error 'An error occured:'
                                log.raw err
                                endUpdate app, callback
                            else

                                log.info " * Stop #{app.name}"
                                stopApp app, (err) ->
                                    if err
                                        log.error 'An error occured:'
                                        log.raw err
                                    endUpdate app, callback

                # When application is installed, try :
                #   * update application
                when 'installed'
                    log.info " * Old status: " + "started".bold
                    log.info " * Update #{app.name}"
                    lightUpdateApp app, (err) ->
                        if err
                            log.error 'An error occured:'
                            log.raw err
                        endUpdate app, callback

                # When application is stopped, try :
                #   * update application
                else
                    log.info " * Old status: " + "stopped".bold
                    log.info " * Update #{app.name}"
                    lightUpdateApp app, (err) ->
                        if err
                            log.error 'An error occured:'
                            log.raw err
                        endUpdate app, callback

    homeClient.host = homeUrl
    homeClient.get "api/applications/", (err, res, apps) ->
        funcs = []
        if apps? and apps.rows?
            for app in apps.rows
                func = updateApp app
                funcs.push func

            async.series funcs, ->
                log.info "\nAll apps reinstalled."
                log.info "Reset proxy routes"

                statusClient.host = proxyUrl
                statusClient.get "routes/reset", (err, res, body) ->
                    if err
                        handleError err, body, "Cannot reset proxy routes."
                    else
                        log.info "Resetting proxy routes succeeded."


# Versions
module.exports.getVersion = (app, callback) ->
    homeClient.host = homeUrl
    homeClient.get "api/applications/", (err, res, apps) ->
        if apps?.rows?
            log.raw "#{app.name}: #{app.version}" for app in apps.rows
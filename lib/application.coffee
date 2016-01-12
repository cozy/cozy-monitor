async = require "async"
fs = require "fs"
axon = require 'axon'
spawn = require('child_process').spawn
exec = require('child_process').exec
path = require('path')
log = require('printit')()
request = require("request-json-light")
colors = require "colors"

helpers = require './helpers'
homeClient = helpers.clients.home
proxyClient = helpers.clients.proxy
dsClient = helpers.clients.ds
client = helpers.clients.controller
handleError = helpers.handleError
makeError = helpers.makeError
getToken = helpers.getToken

# Applications helpers #


# Define random function for application's token
randomString = (length) ->
    string = ""
    while (string.length < length)
        string = string + Math.random().toString(36).substr(2)
    return string.substr 0, length

setIcon = (manifest, callback) ->
    homeClient.headers['content-type'] = 'application/json'
    homeClient.get 'api/applications/market', (err, res, body) ->
        found = false
        if body?
            for app in body
                if app.name is manifest.name
                    found = true
                    callback app.icon
        if not found
            callback ''

waitInstallComplete = (slug, timeout, callback) ->
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
    unless timeout?
        timeout = 240000
    if timeout isnt 'false'
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
        , timeout

    socket.on 'application.update', (id) ->

        dsClient.setBasicAuth 'home', token if token = getToken()
        dsClient.get "data/#{id}/", (err, response, body) ->
            if response.statusCode is 401
                dsClient.setBasicAuth 'home', ''
                dsClient.get "data/#{id}/", (err, response, body) ->
                    callback err, body
            else if body.state is 'installed'
                callback err, body
                clearTimeout timeoutId
                socket.close()




# Retrieve application manifest from
#   * its package.json
#   * and its git configuration
retrieveManifestFromDisk = (app, callback) ->
    # Define path
    basePath =  path.join '/usr/local/cozy/apps', app
    configGit = path.join basePath, '.git', 'config'
    jsonPackage = path.join basePath, 'package.json'

    # Retrieve manifest from package.json
    manifest = JSON.parse(fs.readFileSync jsonPackage, 'utf8')

    # Retrieve url for git config
    command = "cd #{basePath} && git config --get remote.origin.url"
    exec command, (err, body) ->
        return callback err if err?
        manifest.git = body.replace '\n', ''

        # Retrieve branch from git config
        command = "cd #{basePath} && git branch"
        exec "cd #{basePath} && git branch", (err, body) ->
            return callback err if err?
            # Body as form as :
            ##  <other_branch>
            ##* <current_branch>
            ##  <other_branch>
            body = body.split '\n'
            for branch in body
                if branch.indexOf('*') isnt -1
                    manifest.branch = branch.replace '* ', ''
                    callback null, manifest



msgHomeNotStarted = (app) ->
    return """
            Install home failed for #{app}. The Cozy Home looks not started.
            Install operation cannot be performed.
        """

msgRepoGit = (app) ->
    return """
            Install home failed for #{app}.
            Default git repo #{manifest.git} doesn't exist.
            You can use option -r to use a specific repo.
        """

msgLongInstall = (app) ->
    return """
            #{app} installation is still running. You should check for
            its status later. If the installation is too long, you should try
            to stop it by uninstalling the application and running the
            installation again.
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
       "start": "build/server.js"

# Applications functions #

# Callback all application stored in database
module.exports.getApps = (callback) ->
    homeClient.get "api/applications/", (error, res, apps) ->
        if apps? and apps.rows?
            callback null, apps.rows
        else
            # Check if couch is available
            helpers.clients['couch'].get '', (err, res, body) ->
                if err or not res? or res.statusCode isnt 200
                    log.error "CouchDB looks not started"
                # Check if data-system is available
                helpers.clients['ds'].get '', (err, res, body) ->
                    if not res? or res.statusCode isnt 200
                        log.error "The Cozy Data System looks not started"
                    # Check if home is available
                    helpers.clients['home'].get '', (err, res, body) ->
                        if not res? or res.statusCode isnt 200
                            log.error "The Cozy Home looks not started"
                        # Other pbs: credentials, view, ...
                        callback makeError(error, apps)


retrieveGit = (app, options, callback) ->
    if options.repo
        # If repository is specified callback it
        callback options.repo
    else
        # Check if application exists in market
        homeClient.get 'api/applications/market', (err, res, market) ->
            if err
                log.error "Can't fetch the market"
                log.error err
                callback "https://github.com/cozy/cozy-#{app}.git"
            else
                async.filter market, (appli, cb) ->
                    cb appli.name is app
                , (appliMarket) ->
                    if appliMarket.length > 0
                        callback appliMarket[0].git
                    else
                        # Callback default repository
                        callback "https://github.com/cozy/cozy-#{app}.git"



# Install application <app>
install = module.exports.install = (app, options, callback) ->
    recoverManifest = (callback) ->
        # Create manifest
        manifest.name = app
        if options.displayName?
            manifest.displayName = options.displayName
        else
            manifest.displayName = app
        manifest.user = app
        retrieveGit app, options, (git) ->
            manifest.git = git
            # Check if repository have option branch after '@'
            repo = git.split '@'
            manifest.git = repo[0]
            if repo.length is 2 and not options.branch?
                options.branch = repo[1]
            # Add ;git if it omitted
            if manifest.git.indexOf('.git') is -1
                manifest.git += '.git'
            if options.branch?
                manifest.branch = options.branch
            path = "api/applications/install"
            # Retrieve application icon
            setIcon manifest, (icon) ->
                manifest.icon = icon
                callback manifest

    recoverManifest (manifest) ->
        homeClient.headers['content-type'] = 'application/json'
        homeClient.post path, manifest, (err, res, body) ->
            if err or body.error
                if err?.code is 'ECONNREFUSED'
                    err = makeError msgHomeNotStarted(app), null
                else if body?.message?.indexOf('Not Found') isnt -1
                    err = makeError msgRepoGit(app), null
                else
                    err = makeError err, body
                callback err
            else
                slug = body.app.slug
                waitInstallComplete slug, options.timeout, (err, appresult) ->
                    if err
                        callback makeError(err, null)
                    else if appresult.state is 'installed'
                        callback()
                    else if appresult.state is 'installing'
                        callback makeError(msgLongInstall(app), null)
                    else
                        callback makeError(msgInstallFailed(app), null)


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
                homeClient.post path, {}, (err, res, body) ->
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
module.exports.update = (app, callback) ->
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
                            # Force authentication
                            process.env.NAME = "home"
                            process.env.TOKEN = helpers.getToken()
                            process.env.NODE_ENV = "production"
                            # remove update notification
                            NotificationsHelper = require 'cozy-notifications-helper'
                            notifier = new NotificationsHelper 'home'
                            notificationSlug = """
                              home_update_notification_app_#{app}
                            """
                            notifier.destroy notificationSlug, (err) ->
                                log.error err if err?
                                callback()
            if not find
                err = "Update failed: application #{app} not found."
                callback makeError(err, null)
        else
            err = "Update failed: no application installed"
            callback makeError(err, null)


# Change stack application branch
module.exports.changeBranch = (app, branch, callback) ->
    find = false
    homeClient.get "api/applications/", (err, res, apps) ->
        if apps? and apps.rows?
            for manifest in apps.rows
                if manifest.name is app
                    find = true
                    path = "api/applications/#{manifest.slug}/branch/#{branch}"
                    homeClient.put path, manifest, (err, res, body) ->
                        if err or body.error
                            callback makeError(err, body)
                        else
                            callback()
            if not find
                err = "Update failed: application #{app} not found."
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
    log.info "    * uninstall #{app}"
    uninstall app, (err) ->
        if err
            log.error '     -> KO'
            callback err
        else
            log.info '     -> OK'
            log.info "    * install #{app}"
            install app, options, (err)->
                if err
                    log.error '     -> KO'
                else
                    log.info '     -> OK'
                callback err

# Intall application <app> from disk to database.
module.exports.installFromDisk = (app, callback) ->
    options = {'headers': {'content-type': 'application/json'}}
    retrieveManifestFromDisk app, (err, manifest) ->

        # Create application document
        appli =
            docType: "application"
            displayName: manifest.displayName or manifest.name.replace 'cozy-', ''
            name: manifest.name.replace 'cozy-', ''
            slug: manifest.name.replace 'cozy-', ''
            version: manifest.version
            isStoppable: false
            git: manifest.git
            branch: manifest.branch
            state: 'installed'
            iconPath: "img/apps/#{app}.svg"
            iconType: 'svg'
            port: null
        clientCouch = helpers.clients.couch
        [id, pwd] = helpers.getAuthCouchdb(false)
        couchClient.setBasicAuth id, pwd if id isnt ''
        clientCouch.post helpers.dbName, appli, options, (err, res, app) ->
            return callback err if err?
            return callback app.error if app.error?

            # Create access document
            access =
                docType: 'Access'
                login: appli.name
                token: randomString()
                permissions: manifest['cozy-permissions']
                app: app.id
            clientCouch.post helpers.dbName, access, options, (err, res, body) ->
                return callback err if err?
                return callback app.error if app.error?

                # Add icon
                homePath = '/usr/local/cozy/apps/home/client/app/assets'
                iconPath = path.join homePath, appli.iconPath
                urlPath = "#{helpers.dbName}/#{app.id}/icon.svg?rev=#{app.rev}"
                clientCouch.putFile urlPath, iconPath, (err, res, body) ->
                    callback()



# Install without home (usefull for relocation)
module.exports.installController = (app, callback) ->
    log.info "    * install #{app.slug}"
    client.stop app.slug, (err, res, body) ->
        # Retrieve application manifest
        manifest.name = app.slug
        manifest.user = app.slug
        manifest.repository.url = app.git
        dsClient.setBasicAuth 'home', token if token = getToken()
        dsClient.post 'request/access/byApp/', key: app.id, (err, res, body) ->
            manifest.password = body[0].value.token
            if app.branch?
                manifest.repository.branch = app.branch
            # Install (or start) application
            client.start manifest, (err, res, body) ->
                if err or body.error
                    log.error '     -> KO'
                    callback makeError(err, body)
                else
                    log.info '     -> OK'
                    if body.drone.port isnt app.port and app.state is 'installed'
                        # Update port if it has changed
                        app.port = body.drone.port
                        log.info "    * update port"
                        dsClient.put "data/#{app.id}/", app, (err, res, body) ->
                            if err or body?.error
                                log.error '     -> KO'
                                callback makeError(err, body)
                            else
                                log.info '     -> OK'
                                callback()
                    else
                        callback()

# Stop application without home (usefull for relocation)
module.exports.stopController = (app, callback) ->
    log.info "    * stop #{app}"
    # Stop application
    client.stop app, (err, res, body) ->
        if err
            log.error '     -> KO'
            callback makeError(err, body)
        else
            log.info '     -> OK'
            callback()


# Callback application version
module.exports.getVersion = (app, callback) ->
    callback app.version


# Callback application state
module.exports.check = (options, app, url) ->
    (callback) ->
        colors.enabled = not options.raw? and not options.json?
        statusClient = request.newClient url
        statusClient.get "", (err, res) ->
            badStatusCode = res? and not res.statusCode in [200, 403]
            econnRefused = err? and err.code is 'ECONNREFUSED'
            if badStatusCode or econnRefused
                if not options.json
                    log.raw "#{app}: " + "down".red
                callback null, [app, 'down'] if callback?
            else
                if not options.json
                    log.raw "#{app}: " + "up".green
                callback null, [app, 'up'] if callback?


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
            dsClient.del "access/#{app._id}/", (err, response, body) ->
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
            manifest.displayName =
                manifest['cozy-displayName'] or manifest.name
            manifest.state = "installed"
            manifest.docType = "Application"
            manifest.port = port
            manifest.slug = manifest.name.replace 'cozy-', ''

            access =
                permissions: manifest['cozy-permissions']
                password: randomString()
                slug: manifest.slug

            if manifest.slug in ['hometest', 'proxytest', 'data-systemtest']
                log.error(
                    'Sorry, cannot start stack application without ' +
                    ' controller.')
                cb()
            else
                cb(manifest, access)


    putInDatabase = (manifest, access, cb) ->
        log.info "Add/replace application in database..."
        token = getToken()
        if token?
            dsClient.setBasicAuth 'home', token
            requestPath = "request/application/all/"
            dsClient.post requestPath, {}, (err, response, apps) ->
                log.error "Data-system looks down (not responding)." if err?
                return cb() if err?
                removeApp apps, manifest.name, () ->
                    dsClient.post "data/", manifest, (err, res, body) ->
                        id = body._id
                        if err
                            log.error "Cannot add application in database."
                            cb makeError(err, body)
                        else
                            access.app = id
                            dsClient.post "access/", access, (err, res, body) ->
                                if err
                                    msg = "Cannot add application in database."
                                    log.error msg
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
    recoverManifest (manifest, access) ->
        # Add/Replace application in database
        putInDatabase manifest, access, (err) ->
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
                    process.env.TOKEN = access.password
                    process.env.NAME = access.slug
                    process.env.NODE_ENV = "production"
                    process.env.PORT = port

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
        dsClient.post requestPath, {}, (err, response, apps) ->
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

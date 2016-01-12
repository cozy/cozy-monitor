colors = require "colors"

program = require 'commander'
async = require "async"
fs = require "fs"
axon = require 'axon'
exec = require('child_process').exec
path = require('path')
log = require('printit')()
request = require("request-json-light")


helpers = require './helpers'
homeClient = helpers.clients.home
client = helpers.clients.controller
makeError = helpers.makeError

appsPath = '/usr/local/cozy/apps'

manifest =
   "domain": "localhost"
   "repository":
       "type": "git"
   "scripts":
       "start": "build/server.js"

msgControllerNotStarted = (app) ->
    return """
            Install failed for #{app}. The Cozy Controller looks not started.
            Install operation cannot be performed.
        """

msgRepoGit = (app) ->
    return """
            Install failed for #{app}.
            Default git repo #{manifest.repository.url} doesn't exist.
            You can use option -r to use a specific repo.
        """

# Retrieve application manifest from
#   * its package.json
#   * and its git configuration
retrieveManifest = (app, callback) ->
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
        manifest.repository =
            type: 'git'
            url: body.replace '\n', ''

        # Retrieve branch from git config
        exec command, (err, body) ->
            return callback err if err?
            # Body as form as :
            ##  <other_branch>
            ##* <current_branch>
            ##  <other_branch>
            body = body.split '\n'
            for branch in body
                if branch.indexOf('*') isnt -1
                    manifest.repository.branch = branch.replace '* ', ''
                    callback null, manifest



# Install stack application
module.exports.install = (app, options, callback) ->
    # Create manifest
    manifest.name = app
    manifest.user = app
    manifest.repository.url = options.repo or
            "https://github.com/cozy/cozy-#{app}.git"
    if options.branch?
        manifest.repository.branch = options.branch
    client.clean manifest, (err, res, body) ->
        if err or body.error
            callback makeError(err, body)
        else
            client.start manifest, (err, res, body) ->
                if err or body.error
                    console.log err
                    console.log body
                    if err?.code is 'ECONNREFUSED'
                        err = makeError msgControllerNotStarted(app), null
                    else if body?.message?.indexOf('Not Found') isnt -1
                        err = makeError msgRepoGit(app), null
                    else
                        err = makeError err, body
                    callback err
                else
                    callback()

# Uninstall stack application
module.exports.uninstall = (app, callback) ->
    manifest.name = app
    manifest.user = app
    client.clean manifest, (err, res, body) ->
        if err or body.error?
            callback makeError(err, body)
        else
            callback()

# Restart stack application
module.exports.start = (app, callback) ->
    manifest.name = app
    manifest.repository.url =
        "https://github.com/cozy/cozy-#{app}.git"
    manifest.user = app
    client.stop app, (err, res, body) ->
        client.start manifest, (err, res, body) ->
            if err or body.error?
                callback makeError(err, body)
            else
                callback()


# Stop
module.exports.stop = (app, callback) ->
    manifest.name = app
    manifest.user = app
    client.stop app, (err, res, body) ->
        if err or body.error?
            callback makeError(err, body)
        else
            callback()

# Update
module.exports.update = (app, callback) ->
    manifest.name = app
    # Retrieve manifest
    retrieveManifest app, (err, manifest) ->
        manifest.name = app
        manifest.user = app
        client.lightUpdate manifest, (err, res, body) ->
            if err or body.error?
                callback makeError(err, body)
            else
                # check whether other stack applications need update
                getVersions (err, versions) ->
                    if err
                        # Data-system can be updated even if home is stopped.
                        callback()
                    else
                        needsUpdate = versions.some (app) ->
                            return app.needsUpdate
                        if needsUpdate > 0
                            callback()
                        else
                            # Force authentication
                            process.env.NAME = "home"
                            process.env.TOKEN = helpers.getToken()
                            process.env.NODE_ENV = "production"
                            # remove update notification
                            NotificationsHelper = require 'cozy-notifications-helper'
                            notifier = new NotificationsHelper 'home'
                            notificationSlug = """
                              home_update_notification_stack
                            """
                            notifier.destroy notificationSlug, (err) ->
                                log.error err if err?
                                callback()

# Change stack application branch
module.exports.changeBranch = (app, branch, callback) ->
    manifest.name = app
    # Retrieve manifest
    retrieveManifest app, (err, manifest) ->
        manifest.name = app
        manifest.user = app
        client.changeBranch manifest, branch, (err, res, body) ->
            if err or body.error?
                callback makeError(err, body)
            else
                callback()

waitUpdate = (callback) ->
    homeClient.get '', (err, res, body) ->
        if not res?
            waitUpdate callback
        else
            callback()

# Update all stack
module.exports.updateAll = (callback) ->
    client.updateStack "blockMonitor": true, (err, res, body) ->
        if not res?
            waitUpdate callback
        else if err or body.error?
            callback makeError(err, body)
        else
            callback()

# Callback application version
module.exports.getVersion = getVersion = (name, callback) ->
    if name is "controller"
        path = "/usr/local/lib/node_modules/cozy-controller/package.json"
    else
        path = "#{appsPath}/#{name}/#{name}/cozy-#{name}/package.json"
    if fs.existsSync path
        data = fs.readFileSync path, 'utf8'
        data = JSON.parse data
        callback data.version
    else
        if name is 'controller'
            path = "/usr/lib/node_modules/cozy-controller/package.json"
        else
            path = "#{appsPath}/#{name}/package.json"
        if fs.existsSync path
            data = fs.readFileSync path, 'utf8'
            data = JSON.parse data
            callback data.version
        else
            callback "unknown"

# Get version of every stack application, using the Home API by default
module.exports.getVersions = getVersions = (callback) ->
    cozyStack = ['controller', 'data-system', 'home', 'proxy']
    homeClient.get '/api/applications/stack', (err, res, body) ->
        if err?
            callback makeError(err, null)
        else
            res = {}
            body.rows.forEach (app) ->
                needsUpdate = false
                if app.version? and app.lastVersion?
                    currVersion = app.version.split '.'
                    lastVersion = app.lastVersion.split '.'
                    if lastVersion[0] > currVersion[0]
                        needsUpdate = true
                    else if lastVersion[1] > currVersion[1]
                        needsUpdate = true
                    else if lastVersion[2] > currVersion[2]
                        needsUpdate = true
                res[app.name] =
                    name: app.name
                    version: app.version or 'unknown'
                    lastVersion: app.lastVersion or 'unknown'
                    needsUpdate: needsUpdate

            async.map cozyStack, (app, cb) ->
                if res[app]?
                    cb null, res[app]
                else
                    getVersion app, (version) ->
                        cb null, name: app, version: version, needsUpdate: false
            , callback

# Callback application status
module.exports.check = (options, app, path="") ->
    (callback) ->
        colors.enabled = not options.raw and not options.json
        helpers.clients[app].get path, (err, res) ->
            badStatusCode = res? and not res.statusCode in [200, 403]
            econnRefused = err? and err.code is 'ECONNREFUSED'
            if badStatusCode or econnRefused
                if not options.json
                    log.raw "#{app}: " + "down".red
                callback null, [app, 'down']
            else
                if not options.json
                    log.raw "#{app}: " + "up".green
                callback null, [app, 'up']
        , false

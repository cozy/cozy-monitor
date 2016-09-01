colors = require "colors"

async = require "async"
fs = require "fs"
path = require('path')
log = require('printit')()

helpers = require './helpers'
homeClient = helpers.clients.home
client = helpers.clients.controller
makeError = helpers.makeError

appsPath = '/usr/local/cozy/apps'

msgControllerNotStarted = (app) ->
    return """
            Install failed for #{app}. The Cozy Controller looks not started.
            Install operation cannot be performed.
        """

msgRepoGit = (app, manifest) ->
    return """
            Install failed for #{app}.
            Error not found with manifest
                npm = #{manifest.package}
                git = #{manifest.repository?.url}
            You can use option -r to use a specific repo.
        """


makeManifest = (app, options) ->
    # Create manifest
    manifest =
       "domain": "localhost"
       "repository":
           "type": "git"
       "scripts":
           "start": "build/server.js"

    manifest.name = app
    manifest.user = app

    if options?.repo or options?.branch
        manifest.repository.url = \
            options.repo or  "https://github.com/cozy/cozy-#{app}.git"

        if manifest.repository.url.slice(-4) isnt '.git'
            manifest.repository.url += '.git'

        if options.branch?
            manifest.repository.branch = options.branch

    else
        manifest.repository.url = "https://github.com/cozy/cozy-#{app}.git"
        manifest.package = "cozy-#{app}"

    return manifest


# Install stack application
module.exports.install = (app, options, callback) ->
    manifest = makeManifest app, options
    client.clean manifest, (err, res, body) ->
        client.start manifest, (err, res, body) ->
            if err or body.error
                if err?.code is 'ECONNREFUSED'
                    err = makeError msgControllerNotStarted(app), null
                else if body?.message?.indexOf('Not Found') isnt -1
                    err = makeError msgRepoGit(app, manifest), null
                else
                    err = makeError err, body
                callback err
            else
                callback()


# Uninstall stack application
module.exports.uninstall = (app, callback) ->
    manifest = makeManifest app
    client.clean manifest, (err, res, body) ->
        if err or body.error?
            callback makeError(err, body)
        else
            callback()


# Restart stack application
module.exports.start = (app, callback) ->
    manifest = makeManifest app
    client.stop app, (err, res, body) ->
        client.start manifest, (err, res, body) ->
            if err or body.error?
                callback makeError(err, body)
            else
                callback()


# Stop
module.exports.stop = (app, callback) ->
    client.stop app, (err, res, body) ->
        if err or body.error?
            callback makeError(err, body)
        else
            callback()


# Update
module.exports.update = (app, callback) ->
    # Retrieve manifest
    helpers.retrieveManifestFromDisk app, (err, manifest) ->
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
                        if needsUpdate
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
    # Retrieve manifest
    helpers.retrieveManifestFromDisk app, (err, manifest) ->
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
        # Try to get manifest for a NPM application.
        path = "#{appsPath}/#{name}/node_modules/cozy-#{name}/package.json"

        # If it doesn't exist get the manifest from the git repo.
        if not fs.existsSync path
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
                    if parseInt(lastVersion[0], 10) > parseInt(currVersion[0], 10)
                        needsUpdate = true
                    else if parseInt(lastVersion[1], 10) > parseInt(currVersion[1], 10)
                        needsUpdate = true
                    else if parseInt(lastVersion[2], 10) > parseInt(currVersion[2], 10)
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


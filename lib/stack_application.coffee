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

installStackApp = (app, callback) ->
    if typeof app is 'string'
        manifest =
            repository:
                url: "https://github.com/cozy/cozy-#{app}.git"
                type: "git"
            "scripts":
                "start": "build/server.js"
            name: app
            user: app
    else
        manifest = app
    log.info "Install started for #{manifest.name}..."
    client.clean manifest, (err, res, body) ->
        client.start manifest, (err, res, body)  ->
            if err or body.error?
                handleError err, body, "Install failed for #{manifest.name}."
            else
                log.info "#{manifest.name} was successfully installed."


manifest =
   "domain": "localhost"
   "repository":
       "type": "git"
   "scripts":
       "start": "server.coffee"

module.exports.install = (app, options) ->
    # Create manifest
    manifest.name = app
    manifest.user = app

    unless options.repo?
        manifest.repository.url =
            "https://github.com/cozy/cozy-#{app}.git"
    else
        manifest.repository.url = options.repo
    if options.branch?
        manifest.repository.branch = options.branch
    installStackApp manifest, (err) ->
            if err
                handleError err, null, "Install failed"
            else
                log.info "#{app} successfully installed"


# Install cozy stack (home, ds, proxy)
program
    .command("install-cozy-stack")
    .description("Install cozy via the Cozy Controller")
    .action () ->
        installStackApp 'data-system', () ->
            installStackApp 'home', () ->
                installStackApp 'proxy', () ->
                    log.info 'Cozy stack successfully installed.'


module.exports.uninstall = (app) ->
    log.info "Uninstall started for #{app}..."
    manifest.name = app
    manifest.user = app
    client.clean manifest, (err, res, body) ->
        if err or body.error?
            handleError err, body, "Uninstall failed for #{app}."
        else
            log.info "#{app} was successfully uninstalled."

module.exports.start = (app) ->
    log.info "Starting #{app}..."
    manifest.name = app
    manifest.repository.url =
        "https://github.com/cozy/cozy-#{app}.git"
    manifest.user = app
    client.stop app, (err, res, body) ->
        client.start manifest, (err, res, body) ->
            if err or body.error?
                handleError err, body, "Start failed for #{app}."
            else
                log.info "#{app} was successfully started."


# Stop
module.exports.stop = (app) ->
    log.info "Stopping #{app}..."
    manifest.name = app
    manifest.user = app
    client.stop app, (err, res, body) ->
        if err or body.error?
            handleError err, body, "Stop failed"
        else
            log.info "#{app} was successfully stopped."


# Restart
module.exports.restart = (app) ->
        log.info "Stopping #{app}..."
        client.stop app, (err, res, body) ->
            if err or body.error?
                handleError err, body, "Stop failed."
            else
                log.info "#{app} successfully stopped."
                log.info "Starting #{app}..."
                manifest.name = app
                manifest.repository.url =
                    "https://github.com/cozy/cozy-#{app}.git"
                manifest.user = app
                client.start manifest, (err, res, body) ->
                    if err
                        handleError err, body, "Start failed for #{app}"
                    else
                        log.info "#{app} sucessfully started."

# Update
module.exports.update = (app, repo) ->
    log.info "Updating #{app}..."
    manifest.name = app
    if repo?
        manifest.repository.url = repo
    else
        manifest.repository.url =
            "https ://github.com/cozy/cozy-#{app}.git"
    manifest.user = app
    client.lightUpdate manifest, (err, res, body) ->
        if err or body.error?
            handleError err, body, "Update failed."
        else
            log.info "#{app} was successfully updated."


module.exports.updateController = (callback) ->
    log.info "Update controller ..."
    exec "npm -g update cozy-controller", (err, stdout) ->
        if err
            handleError err, null, "Light update failed."
        else
            log.info "Controller was successfully updated."
            callback null

module.exports.restartController = (callback) ->
    log.info "Restart controller ..."
    exec "supervisorctl restart cozy-controller", (err, stdout) ->
        if err
            handleError err, null, "Light update failed."
        else
            log.info "Controller was successfully restarted."
            callback null

module.exports.getVersion = (name) =>
    if name is "controller"
        path = "/usr/local/lib/node_modules/cozy-controller/package.json"
    else
        path = "#{appsPath}/#{name}/#{name}/cozy-#{name}/package.json"
    if fs.existsSync path
        data = fs.readFileSync path, 'utf8'
        data = JSON.parse data
        log.raw "#{name}: #{data.version}"
    else
        if name is 'controller'
            path = "/usr/lib/node_modules/cozy-controller/package.json"
        else
            path = "#{appsPath}/#{name}/package.json"
        if fs.existsSync path
            data = fs.readFileSync path, 'utf8'
            data = JSON.parse data
            log.raw "#{name}: #{data.version}"
        else
            log.raw "#{name}: unknown"


getVersionIndexer = (callback) =>
    client = request.newClient indexerUrl
    client.get '', (err, res, body) =>
        if body? and body.split('v')[1]?
            callback  body.split('v')[1]
        else
            callback "unknown"
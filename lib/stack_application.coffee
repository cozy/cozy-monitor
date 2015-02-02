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
homeClient = helpers.clients.home
indexClient = helpers.clients.index
client = helpers.clients.controller
makeError = helpers.makeError

appsPath = '/usr/local/cozy/apps'


manifest =
   "domain": "localhost"
   "repository":
       "type": "git"
   "scripts":
       "start": "build/server.js"

# Install stack application
module.exports.install = (app, options, callback) ->
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

    client.clean manifest, (err, res, body) ->
        client.start manifest, (err, res, body) ->
            callback(makeError(err, body))

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
module.exports.update = (app, repo, callback) ->
    manifest.name = app
    if repo?
        manifest.repository.url = repo
    else
        manifest.repository.url =
            "https ://github.com/cozy/cozy-#{app}.git"
    manifest.user = app
    client.lightUpdate manifest, (err, res, body) ->
        if err or body.error?
            callback makeError(err, body)
        else
            callback()

# Update all stack
module.exports.updateAll = (callback) ->
    client.updateStack (err, res, body) ->
        if err or body.error?
            callback makeError(err, body)
        else
            callback()

getVersionIndexer = (callback) =>
    indexClient.get '', (err, res, body) =>
        if body? and body.split('v')[1]?
            callback  body.split('v')[1]
        else
            callback "unknown"

module.exports.getVersion = (name, callback) =>
    if name is "indexer"
        getVersionIndexer callback
    else
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

module.exports.check = (app, path="") ->
    (callback) ->
        helpers.clients[app].get path, (err, res) ->
            if (res? and not res.statusCode in [200,403]) or (err? and
                err.code is 'ECONNREFUSED')
                    log.raw "#{app}: " + "down".red
            else
                log.raw "#{app}: " + "up".green
            callback()
        , false



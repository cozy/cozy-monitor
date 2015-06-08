require "colors"

program = require 'commander'
async = require "async"
fs = require "fs"
axon = require 'axon'
exec = require('child_process').exec
spawn = require('child_process').spawn
path = require('path')
log = require('printit')()

helpers = require './helpers'

couchClient = helpers.clients.couch
getAuthCouchdb = helpers.getAuthCouchdb
makeError = helpers.makeError

couchdbHost = process.env.COUCH_HOST or 'localhost'
couchdbPort = process.env.COUCH_PORT or '5984'
couchUrl = "http://#{couchdbHost}:#{couchdbPort}/"

request = require("request-json-light")


## Database helpers ##

# Configure couchClient
configureCouchClient = (callback) ->
    [username, password] = getAuthCouchdb()
    couchClient.setBasicAuth username, password

# Wait end of compaction
waitCompactComplete = (client, found, callback) ->
    setTimeout ->
        client.get '_active_tasks', (err, res, body) ->
            exist = false
            for task in body
                if task.type is "database_compaction"
                    exist = true
            if (not exist) and found
                callback true
            else
                waitCompactComplete(client, exist, callback)
    , 500

# Prepare cozy database
#     * usefull for reverse backup
prepareCozyDatabase = (username, password, callback) ->
    createDatabase = (count, cb) ->
        if count < 5
            couchClient.put "cozy", {}, (err, res, body) ->
                if res.statusCode is 412
                    setTimeout () ->
                        createDatabase count+1, cb
                    , 5 * 1000
                else
                    callback err
        else
            callback 'Cannot create database'

    couchClient.setBasicAuth username, password

    # Remove cozy database
    couchClient.del "cozy", (err, res, body) ->
        # Create new cozy database
        createDatabase 0, (err) ->
            # Add member in cozy database
            data =
                "admins":
                    "names":[username]
                    "roles":[]
                "readers":
                    "names":[username]
                    "roles":[]
            couchClient.put 'cozy/_security', data, (err, res, body)->
                if err?
                    console.log err
                    process.exit 1
                callback()


## Database functions ##

# Compaction #

# Compact database <database>
module.exports.compact = (database, callback)->
    configureCouchClient()

    couchClient.headers['content-type'] = 'application/json'
    couchClient.post "#{database}/_compact", {}, (err, res, body) ->
        if err or not body.ok
            callback makeError(err, body)
        else
            waitCompactComplete couchClient, false, (success) ->

# Comapct view <view> in database <database>
compactViews = module.exports.compactViews = (view, database, callback) ->
    [username, password] = getAuthCouchdb()
    couchClient.setBasicAuth username, password
    path = "#{database}/_compact/#{view}"
    couchClient.headers['content-type'] = 'application/json'
    couchClient.post path, {}, (err, res, body) ->
        if err or not body.ok
            callback makeError(err, body)
        else
            callback()

# Compact all views in database
module.exports.compactAllViews = (database, callback) ->
    configureCouchClient()
    path = "#{database}/_all_docs?startkey=\"_design/\"&endkey=" +
        "\"_design0\"&include_docs=true"

    couchClient.get path, (err, res, body) ->
        if err or not body.rows
            callback makeError(err, body)
        else
            designs = []
            async.eachSeries body.rows, (design, callback) ->
                designId = design.id
                designDoc = designId.substring 8, designId.length
                compactViews designDoc, database, callback
            , (err) ->
                callback(err)

# Cleanup database
module.exports.cleanup = (database, callback) ->
    configureCouchClient()
    couchClient.post "#{database}/_view_cleanup", {}, (err, res, body) ->
        if err or not body.ok
            callback makeError(err, body)
        else
            callback()

# Backup #

# Backup database
module.exports.backup = (data, callback) ->
    configureCouchClient()
    couchClient.post "_replicate", data, (err, res, body) ->
        if err or not body.ok
            callback makeError(err, body)
        else
            callback()

# Reverse backup
module.exports.reverseBackup = (backup, usernameBackup,  passwordBackup, cb) ->
    [username, password] = getAuthCouchdb()
    prepareCozyDatabase username, password, ->
        toBase64 = (str) ->
            new Buffer(str).toString('base64')

        # Initialize creadentials for backup
        credentials = "#{usernameBackup}:#{passwordBackup}"
        basicCredentials = toBase64 credentials
        authBackup = "Basic #{basicCredentials}"

        # Initialize creadentials for cozy database
        credentials = "#{username}:#{password}"
        basicCredentials = toBase64 credentials
        authCozy = "Basic #{basicCredentials}"

        # Initialize data for replication
        data =
            'source':
                'url': backup
                'headers':
                    'Authorization': authBackup
            'target':
                'url': "#{couchUrl}cozy"
                'headers':
                    'Authorization': authCozy

        # Database replication
        couchClient.headers['content-type'] = 'application/json'
        couchClient.post "_replicate", data, (err, res, body) ->
            if err or not body.ok
                cb makeError(err, body)
            else
                cb()
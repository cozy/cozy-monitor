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


## Database ##


compactViews = (database, designDoc, callback) ->
    [username, password] = getAuthCouchdb()
    couchClient.setBasicAuth username, password
    path = "#{database}/_compact/#{designDoc}"
    couchClient.headers['content-type'] = 'application/json'
    couchClient.post path, {}, (err, res, body) =>
        if err or not body.ok
            handleError err, body, "compaction failed for #{designDoc}"
        else
            callback null


compactAllViews = (database, designs, callback) ->
    if designs.length > 0
        design = designs.pop()
        log.info "Views compaction for #{design}"
        compactViews database, design, (err) =>
            compactAllViews database, designs, callback
    else
        callback null


configureCouchClient = (callback) ->
    [username, password] = getAuthCouchdb()
    couchClient.setBasicAuth username, password

#options: {client, foound)
waitCompactComplete = (options, callback) ->
    setTimeout ->
        client.get '_active_tasks', (err, res, body) =>
            exist = false
            for task in body
                if task.type is "database_compaction"
                    exist = true
            if (not exist) and found
                callback true
            else
                waitCompactComplete(client, exist, callback)
    , 500

#options : [username, password]
prepareCozyDatabase = (options, callback) ->
    couchClient.setBasicAuth username, password

    # Remove cozy database
    couchClient.del "cozy", (err, res, body) ->
        # Create new cozy database
        couchClient.put "cozy", {}, (err, res, body) ->
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

#options = database
module.exports.compact = (options, callback)->
    database ?= "cozy"
    configureCouchClient()

    log.info "Start couchdb compaction on #{database} ..."
    couchClient.headers['content-type'] = 'application/json'
    couchClient.post "#{database}/_compact", {}, (err, res, body) ->
        if err or not body.ok
            handleError err, body, "Compaction failed."
        else
            waitCompactComplete couchClient, false, (success) =>
                log.info "#{database} compaction succeeded"
                process.exit 0

#options = database
module.exports.compactViews = (options, callback) ->
    database ?= "cozy"
    log.info "Start vews compaction on #{database} for #{view} ..."
    compactViews database, view, (err) =>
        if not err
            log.info "#{database} compaction for #{view} succeeded"
            process.exit 0

#options = database
module.exports.compactAllViews = (options, callback) ->
    database ?= "cozy"
    configureCouchClient()

    log.info "Start vews compaction on #{database} ..."
    path = "#{database}/_all_docs?startkey=\"_design/\"&endkey=" +
        "\"_design0\"&include_docs=true"

    couchClient.get path, (err, res, body) =>
        if err
            handleError err, body, "Views compaction failed. " +
                "Cannot recover all design documents"
        else
            designs = []
            body.rows.forEach (design) ->
                designId = design.id
                designDoc = designId.substring 8, designId.length
                designs.push designDoc

            compactAllViews database, designs, (err) =>
                if not err
                    log.info "Views are successfully compacted"

#options = database
module.exports.cleanup = (options, callback) ->
    database ?= "cozy"
    log.info "Start couchdb cleanup on #{database}..."
    configureCouchClient()
    couchClient.post "#{database}/_view_cleanup", {}, (err, res, body) ->
        if err or not body.ok
            handleError err, body, "Cleanup failed."
        else
            log.info "#{database} cleanup succeeded"
            process.exit 0

## Backup ##
#options = target
module.exports.backup = (options, callback) ->
    data =
        source: "cozy"
        target: target
    configureCouchClient()
    couchClient.post "_replicate", data, (err, res, body) ->
        if err or not body.ok
            handleError err, body, "Backup failed."
        else
            log.info "Backup succeeded"
            process.exit 0

#options = username, password, backup
module.exports.reverseBackup = (options, callback) ->
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
            source:
                url: backup
                headers:
                    Authorization: authBackup
            target:
                url: "#{couchUrl}cozy"
                headers:
                    Authorization: authCozy

        # Database replication
        couchClient.post "_replicate", data, (err, res, body) ->
            if err or not body.ok
                handleError err, body, "Backup failed."
            else
                log.info "Reverse backup succeeded"
                process.exit 0
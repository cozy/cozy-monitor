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


## Monitoring ###


module.exports.startDevRoute = (slug, port, callback) ->
    client = request.newClient dataSystemUrl
    client.setBasicAuth 'home', token if token = getToken()

    packagePath = process.cwd() + '/package.json'
    try
        packageData = JSON.parse(fs.readFileSync(packagePath, 'utf8'))
    catch err
        log.error "Run this command in the package.json directory"
        log.raw err
        return

    perms = {}
    for doctype, perm of packageData['cozy-permissions']
        perms[doctype.toLowerCase()] = perm

    data =
        docType: "Application"
        state: 'installed'
        isStoppable: false
        slug: slug
        name: slug
        password: slug
        permissions: perms
        widget: packageData['cozy-widget']
        port: port
        devRoute: true

    client.post "data/", data, (err, res, body) ->
        if err
            handleError err, body, "Create route failed"
        else
            statusClient.host = proxyUrl
            statusClient.get "routes/reset", (err, res, body) ->
                if err
                    handleError err, body, "Reset routes failed"
                else
                    log.info "Route was successfully created."
                    log.info "Start your app with the following ENV vars:"
                    log.info "NAME=#{slug} TOKEN=#{slug} PORT=#{port}"
                    log.info "Use dev-route:stop #{slug} to remove it."


module.exports.stopDevRoute = (slug, callback) ->
        client = request.newClient dataSystemUrl
        client.setBasicAuth 'home', token if token = getToken()
        appsQuery = 'request/application/all/'

        stopRoute = (app) ->
            isSlug = (app.key is slug or slug is 'all')
            if isSlug and app.value.devRoute
                client.del "data/#{app.id}/", (err, res, body) ->
                    if err
                        handleError err, body, "Unable to delete route."
                    else
                        log.info "Route deleted."
                        client.host = proxyUrl
                        client.get 'routes/reset', (err, res, body) ->
                            if err
                                msg = "Stop reseting proxy routes."
                                handleError err, body, msg
                            else
                                log.info "Reseting proxy routes succeeded."


        client.post appsQuery, null, (err, res, apps) ->
            if err or not apps?
                handleError err, apps, "Unable to retrieve apps data."
            else
                apps.forEach stopRoute
            console.log "There is no dev route with this slug"


module.export.getRoutes = (callback) ->
        log.info "Display proxy routes..."

        statusClient.host = proxyUrl
        statusClient.get "routes", (err, res, routes) ->

            if err
                handleError err, {}, "Cannot display routes."
            else if routes?
                for route of routes
                    log.raw "#{route} => #{routes[route].port}"

module.exports.moduleStatus = (module, callback) ->
    urls =
        controller: controllerUrl
        "data-system": dataSystemUrl
        indexer: indexerUrl
        home: homeUrl
        proxy: proxyUrl
    statusClient.host = urls[module]
    statusClient.get '', (err, res) ->
        if not res? or not res.statusCode in [200, 401, 403]
            console.log "down"
        else
            console.log "up"


module.exports.status = (callback) ->
    checkApp = (app, host, path="") ->
        (callback) ->
            statusClient.host = host
            statusClient.get path, (err, res) ->
                if (res? and not res.statusCode in [200,403]) or (err? and
                    err.code is 'ECONNREFUSED')
                        log.raw "#{app}: " + "down".red
                else
                    log.raw "#{app}: " + "up".green
                callback()
            , false

    async.series [
        checkApp "postfix", postfixUrl
        checkApp "couchdb", couchUrl
        checkApp "controller", controllerUrl, "version"
        checkApp "data-system", dataSystemUrl
        checkApp "home", homeUrl
        checkApp "proxy", proxyUrl, "routes"
        checkApp "indexer", indexerUrl
    ], ->
        statusClient.host = homeUrl
        statusClient.get "api/applications/", (err, res, apps) ->
            funcs = []
            if apps? and apps.rows?
                for app in apps.rows
                    if app.state is 'stopped'
                        log.raw "#{app.name}: " + "stopped".grey
                    else
                        url = "http://localhost:#{app.port}/"
                        func = checkApp app.name, url
                        funcs.push func
                async.series funcs, ->

module.exports.log = (app, type, callback) ->
    path = "/usr/local/var/log/cozy/#{app}.log"

    if not fs.existsSync path
        log.error "Log file doesn't exist (#{path})."

    else if type is "cat"
        log.raw fs.readFileSync path, 'utf8'

    else if type is "tail"
        tail = spawn "tail", ["-f", path]

        tail.stdout.setEncoding 'utf8'
        tail.stdout.on 'data', (data) =>
            log.raw data

        tail.on 'close', (code) =>
            log.info "ps process exited with code #{code}"

    else
        log.info "<type> should be 'cat' or 'tail'"
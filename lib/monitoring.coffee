colors = require "colors"
program = require 'commander'
async = require "async"
fs = require "fs"
axon = require 'axon'
spawn = require('child_process').spawn
path = require('path')
log = require('printit')()


application = require './application'
stackApplication = require './stack_application'
helpers = require './helpers'
makeError = helpers.makeError
dsClient = helpers.clients.ds
homeClient = helpers.clients.home
proxyClient = helpers.clients.proxy
getToken = helpers.getToken

## Monitoring ###

# Start proxy route for dev
module.exports.startDevRoute = (slug, port, callback) ->
    dsClient.setBasicAuth 'home', token if token = getToken()
    packagePath = process.cwd() + '/package.json'
    try
        packageData = JSON.parse(fs.readFileSync(packagePath, 'utf8'))
    catch err
        error = "Run this command in the package.json directory"
        callback makeError(err, null)
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

    dsClient.post "data/", data, (err, res, body) ->
        if err
            log.error "Create route failed"
            callback makeError(err, body)
        else
            proxyClient.get "routes/reset", (err, res, body) ->
                if err
                    log.error "Reset routes failed"
                    callback makeError(err, body)
                else
                    log.info "Start your app with the following ENV vars:"
                    log.info "NAME=#{slug} TOKEN=#{slug} PORT=#{port}"
                    log.info "Use dev-route:stop #{slug} to remove it."
                    callback()

# Stop proxy route for dev
module.exports.stopDevRoute = (slug, callback) ->
    found = false
    dsClient.setBasicAuth 'home', token if token = getToken()
    appsQuery = 'request/application/all/'

    stopRoute = (app) ->
        isSlug = (app.value.slug is slug or slug is 'all')
        if isSlug and app.value.devRoute
            found = true
            dsClient.del "data/#{app.id}/", (err, res, body) ->
                if err
                    callback makeError(err, body)
                else
                    log.info "Route deleted."
                    proxyClient.get 'routes/reset', (err, res, body) ->
                        if err
                            log.error "Stop reseting proxy routes."
                            callback makeError(err, body)
                        else
                            callback()


    dsClient.post appsQuery, null, (err, res, apps) ->
        if err or not apps?
            log.error "Unable to retrieve apps data."
            callback makeError(err, apps)
        else
            apps.forEach stopRoute
            if not found
                console.log "There is no dev route with this slug"

# Callback all proxy routes
module.exports.getRoutes = (callback) ->
    proxyClient.get "routes", (err, res, routes) ->
        if err
            callback makeError(err, null)
        else if routes?
            for route of routes
                log.raw "#{route} => #{routes[route].port}"
            callback null, routes

# Callback module state
module.exports.moduleStatus = (module, callback) ->
    if module is "data-system"
        module = 'ds'
    helpers.clients[module].get '', (err, res) ->
        if not res? or not res.statusCode in [200, 401, 403]
            callback "down"
        else
            callback "up"

# Log all applications status
module.exports.status = (options, callback) ->
    colors.enabled = not options.raw? and not options.json?
    async.series [
        stackApplication.check options, "mta"
        stackApplication.check options, "couch"
        stackApplication.check options, "controller", "version"
        stackApplication.check options, "data-system"
        stackApplication.check options, "home"
        stackApplication.check options, "proxy", "routes"
    ], (err, stack) ->
        res = {}
        stack.forEach (app) ->
            res[app[0]] = app[1]
        funcs = []
        application.getApps (err, apps) ->
            if err?
                log.error "Cannot retrieve apps"
                callback err
            else
                for app in apps
                    if app.state is 'stopped'
                        if options.json
                            res[app.name] = "stopped"
                        else
                            log.raw "#{app.name}: " + "stopped".grey
                    # don't need to check app if static
                    else if app.type is 'static'
                        log.raw "#{app.name}: " + "up".green + " (static)".blue
                    else
                        url = "http://localhost:#{app.port}/"
                        func = application.check options, app.name, url
                        funcs.push func
                async.series funcs, (err, apps) ->
                    apps.forEach (app) ->
                        res[app[0]] = app[1]
                    callback null, res

# Display application logs
module.exports.log = (app, type, callback) ->
    path = "/usr/local/var/log/cozy/#{app}.log"
    if not fs.existsSync path
        callback makeError("Log file doesn't exist (#{path}).", null)

    else if type is "cat"
        log.raw fs.readFileSync path, 'utf8'
        callback()

    else if type is "tail"
        tail = spawn "tail", ["-f", path]

        tail.stdout.setEncoding 'utf8'
        tail.stdout.on 'data', (data) ->
            log.raw data

        tail.on 'close', (code) ->
            log.info "ps process exited with code #{code}"

    else
        callback makeError("<type> should be 'cat' or 'tail'", null)

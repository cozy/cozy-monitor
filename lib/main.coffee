# This program is suited only to manage your cozy installation from the inside
# Moreover app management works only for apps make by Cozy Cloud company.
# If you want a friendly application manager you should use the
# appmanager.coffee script.

require "colors"

program = require 'commander'
async = require "async"
fs = require "fs"
axon = require 'axon'
exec = require('child_process').exec
spawn = require('child_process').spawn
log = require('printit')()

request = require("request-json-light")
ControllerClient = require("cozy-clients").ControllerClient

pkg = require '../package.json'
version = pkg.version

couchUrl = "http://localhost:5984/"
dataSystemUrl = "http://localhost:9101/"
indexerUrl = "http://localhost:9102/"
controllerUrl = "http://localhost:9002/"
homeUrl = "http://localhost:9103/"
proxyUrl = "http://localhost:9104/"
postfixUrl = "http://localhost:25/"

homeClient = request.newClient homeUrl
statusClient = request.newClient ''
appsPath = '/usr/local/cozy/apps'



## Helpers


readToken = (file) ->
    try
        token = fs.readFileSync file, 'utf8'
        token = token.split('\n')[0]
        return token
    catch err
        log.info """
Cannot get Cozy credentials. Are you sure you have the rights to access to:
/etc/cozy/stack.token ?
"""
        return null


getToken = ->
    # New controller
    if fs.existsSync '/etc/cozy/stack.token'
        return readToken '/etc/cozy/stack.token'
    else
        # Old controller
        if fs.existsSync '/etc/cozy/controller.token'
            return readToken '/etc/cozy/controller.token'
        else
            return null


getAuthCouchdb = (callback) ->
    fs.readFile '/etc/cozy/couchdb.login', 'utf8', (err, data) =>
        if err
            log.error """
Cannot read database credentials in /etc/cozy/couchdb.login
"""
            callback err
        else
            username = data.split('\n')[0]
            password = data.split('\n')[1]
            callback null, username, password


handleError = (err, body, msg) ->
    log.error "An error occured:"
    console.log err if err
    console.log msg
    if body?
        if body.msg?
           console.log body.msg
        else if body.error?.message?
            console.log body.error.message
            console.log body.error.result
            console.log body.error.code
            console.log body.error.blame
        else console.log body
    process.exit 1


compactViews = (database, designDoc, callback) ->
    client = request.newClient couchUrl
    getAuthCouchdb (err, username, password) ->
        if err
            process.exit 1
        else
            client.setBasicAuth username, password
            path = "#{database}/_compact/#{designDoc}"
            client.post path, {}, (err, res, body) =>
                if err
                    handleError err, body, "compaction failed for #{designDoc}"
                else if not body.ok
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


waitCompactComplete = (client, found, callback) ->
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


waitInstallComplete = (slug, callback) ->
    axon   = require 'axon'
    socket = axon.socket 'sub-emitter'
    socket.connect 9105

    timeoutId = setTimeout ->
        socket.close()

        statusClient.host = homeUrl
        statusClient.get "api/applications/", (err, res, apps) ->
            return unless apps?.rows?

            for app in apps.rows
                console.log slug, app.slug, app.state, app.port
                if app.slug is slug and app.state is 'installed' and app.port
                    statusClient.host = "http://localhost:#{app.port}/"
                    statusClient.get "", (err, res) ->
                        if res?.statusCode in [200, 403]
                            callback null, state: 'installed'
                        else
                            handleError null, null, "Install home failed"
                    return

            handleError null, null, "Install home failed"

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

prepareCozyDatabase = (username, password, callback) ->
    client.setBasicAuth username, password
    # Remove cozy database
    client.del "cozy", (err, res, body) ->
        # Create new cozy database
        client.put "cozy", {}, (err, res, body) ->
            # Add member in cozy database
            data =
                "admins":
                    "names":[username]
                    "roles":[]
                "readers":
                    "names":[username]
                    "roles":[]
            client.put 'cozy/_security', data, (err, res, body)->
                if err?
                    console.log err
                    process.exit 1
                callback()


getVersion = (name) =>
    if name is "controller"
        path = "/usr/local/lib/node_modules/cozy-controller/package.json"
    else
        path = "#{appsPath}/#{name}/#{name}/cozy-#{name}/package.json"
    if fs.existsSync path
        data = fs.readFileSync path, 'utf8'
        data = JSON.parse(data)
        log.info "#{name}: #{data.version}"
    else
        path = "#{appsPath}/#{name}/cozy-#{name}/package.json"
        if fs.existsSync path
            data = fs.readFileSync path, 'utf8'
            data = JSON.parse(data)
            log.info "#{name}: #{data.version}"
        else
            log.info "#{name}: unknown"


getVersionIndexer = (callback) =>
    client = request.newClient 'http://localhost:9102'
    client.get '', (err, res, body) =>
        if body? and body.split('v')[1]?
            callback  body.split('v')[1]
        else
            callback "unknown"


token = getToken()
client = new ControllerClient
    token: token


manifest =
   "domain": "localhost"
   "repository":
       "type": "git"
   "scripts":
       "start": "server.coffee"


program
  .version(version)
  .usage('<action> <app>')


## Applications management ##

# Install
#
program
    .command("install <app> ")
    .description("Install application")
    .option('-r, --repo <repo>', 'Use specific repo')
    .option('-b, --branch <branch>', 'Use specific branch')
    .option('-d, --displayName <displayName>', 'Display specific name')
    .action (app, options) ->
        manifest.name = app
        if options.displayName?
            manifest.displayName = options.displayName
        else
            manifest.displayName = app
        manifest.user = app
        log.info "Install started for #{app}..."
        if app in ['data-system', 'home', 'proxy']
            unless options.repo?
                manifest.repository.url =
                    "https://github.com/cozy/cozy-#{app}.git"
            else
                manifest.repository.url = options.repo
            if options.branch?
                manifest.repository.branch = options.branch
            client.clean manifest, (err, res, body) ->
                client.start manifest, (err, res, body)  ->
                    if err or body.error?
                        handleError err, body, "Install failed"
                    else
                        client.brunch manifest, =>
                            log.info "#{app} successfully installed"
        else
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
                    isIndexOf = body.message.indexOf('Not Found')
                    if body?.message? and  isIndexOf isnt -1
                        err = """
Default git repo #{manifest.git} doesn't exist.
You can use option -r to use a specific repo.
"""
                        handleError err, null, "Install home failed"
                    else
                        handleError err, body, "Install home failed"
                else
                    waitInstallComplete body.app.slug, (err, appresult) ->
                        if not err? and appresult.state is "installed"
                            log.info "#{app} successfully installed"
                        else
                            handleError null, null, "Install home failed"


program
    .command("install-cozy-stack")
    .description("Install cozy via the Cozy Controller")
    .action () ->
        installApp = (name, callback) ->
            manifest.repository.url =
                    "https://github.com/cozy/cozy-#{name}.git"
            manifest.name = name
            manifest.user = name
            log.info "Install started for #{name}..."
            client.clean manifest, (err, res, body) ->
                client.start manifest, (err, res, body)  ->
                    if err or body.error?
                        handleError err, body, "Install failed"
                    else
                        client.brunch manifest, =>
                            log.info "#{name} successfully installed"
                            callback null

        installApp 'data-system', () =>
            installApp 'home', () =>
                installApp 'proxy', () =>
                    log.info 'Cozy stack successfully installed'


# Uninstall
program
    .command("uninstall <app>")
    .description("Remove application")
    .action (app) ->
        log.info "Uninstall started for #{app}..."
        if app in ['data-system', 'home', 'proxy']
            manifest.name = app
            manifest.user = app
            client.clean manifest, (err, res, body) ->
                if err or body.error?
                    handleError err, body, "Uninstall failed"
                else
                    log.info "#{app} successfully uninstalled"
        else
            path = "api/applications/#{app}/uninstall"
            homeClient.del path, (err, res, body) ->
                if err or res.statusCode isnt 200
                    handleError err, body, "Uninstall home failed"
                else
                    log.info "#{app} successfully uninstalled"


program
    .command("uninstall-all")
    .description("Uninstall all apps from controller")
    .action (app) ->
        log.info "Uninstall all apps..."

        client.cleanAll (err, res, body) ->
            if err  or body.error?
                handleError err, body, "Uninstall all failed"
            else
                log.info "All apps successfully uinstalled"


# Start

program
    .command("start <app>")
    .description("Start application")
    .action (app) ->
        log.info "Starting #{app}..."
        if app in ['data-system', 'home', 'proxy']
            manifest.name = app
            manifest.repository.url =
                "https://github.com/cozy/cozy-#{app}.git"
            manifest.user = app
            client.stop app, (err, res, body) ->
                client.start manifest, (err, res, body) ->
                    if err or body.error?
                        handleError err, body, "Start failed"
                    else
                        log.info "#{app} successfully started"
        else
            find = false
            homeClient.host = homeUrl
            homeClient.get "api/applications/", (err, res, apps) ->
                if apps? and apps.rows?
                    for manifest in apps.rows
                        if manifest.name is app
                            find = true
                            path = "api/applications/#{manifest.slug}/start"
                            homeClient.post path, manifest, (err, res, body) ->
                                if err or body.error
                                    handleError err, body, "Start failed"
                                else
                                    log.info "#{app} successfully started"
                    if not find
                        log.error "Start failed : application #{app} not found"
                else
                    log.error "Start failed : no applications installed"


# Stop

program
    .command("stop <app>")
    .description("Stop application")
    .action (app) ->
        log.info "Stopping #{app}..."
        if app in ['data-system', 'home', 'proxy']
            manifest.name = app
            manifest.user = app
            client.stop app, (err, res, body) ->
                if err or body.error?
                    handleError err, body, "Stop failed"
                else
                    log.info "#{app} successfully stopped"
        else
            find = false
            homeClient.host = homeUrl
            homeClient.get "api/applications/", (err, res, apps) ->
                if apps? and apps.rows?
                    for manifest in apps.rows
                        if manifest.name is app
                            find = true
                            path = "api/applications/#{manifest.slug}/stop"
                            homeClient.post path, manifest, (err, res, body) ->
                                if err or body.error
                                    handleError err, body, "Start failed"
                                else
                                    log.info "#{app} successfully stopped"
                    if not find
                        log.error "Stop failed : application #{app} not found"
                else
                    log.error "Stop failed : no applications installed"


program
    .command("stop-all")
    .description("Stop all user applications")
    .action ->

        stopApp = (app) ->
            (callback) ->
                log.info "\nStop #{app.name}..."
                path = "api/applications/#{app.slug}/stop"
                homeClient.post path, app, (err, res, body) ->
                    if err or body.error
                        log.error "\nStopping #{app.name} failed."
                        if err
                            log.raw err
                        else
                            log.raw body.error
                    callback()

        homeClient.host = homeUrl
        homeClient.get "api/applications/", (err, res, apps) ->
            funcs = []
            if apps? and apps.rows?
                for app in apps.rows
                    func = stopApp(app)
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


program
    .command('autostop-all')
    .description("Put all applications in autostop mode" +
        "(except pfm, emails, feeds, nirc and konnectors)")
    .action ->
        unStoppable = ['pfm', 'emails', 'feeds', 'nirc', 'sync', 'konnectors']
        homeClient.host = homeUrl
        homeClient.get "api/applications/", (err, res, apps) ->
            if apps? and apps.rows?
                for app in apps.rows
                    if not(app.name in unStoppable)
                        if not app.isStoppable
                            app.isStoppable = true
                            homeClient.put "api/applications/byid/#{app.id}",
                                app, (err, res) ->
                                   log.error app.name
                                   log.raw err

# Restart

program
    .command("restart <app>")
    .description("Restart application")
    .action (app) ->
        log.info "Stopping #{app}..."
        if app in ['data-system', 'home', 'proxy']
            client.stop app, (err, res, body) ->
                if err or body.error?
                    handleError err, body, "Stop failed"
                else
                    log.info "#{app} successfully stopped"
                    log.info "Starting #{app}..."
                    manifest.name = app
                    manifest.repository.url =
                        "https://github.com/cozy/cozy-#{app}.git"
                    manifest.user = app
                    client.start manifest, (err, res, body) ->
                        if err
                            handleError err, body, "Start failed"
                        else
                            log.info "#{app} sucessfully started"
        else
            path = "api/applications/#{app}/stop"
            homeClient.post path, {}, (err, res, body) ->
                if err or body.error?
                    handleError err, body, "Stop failed"
                else
                    log.info "#{app} successfully stopped"
                    log.info "Starting #{app}..."
                    path = "api/applications/#{app}/start"
                    homeClient.post path, {}, (err, res, body) ->
                        if err
                            handleError err, body, "Start failed"
                        else
                            log.info "#{app} sucessfully started"


program
    .command("restart-cozy-stack")
    .description("Restart cozy trough controller")
    .action () ->
        restartApp = (name, callback) ->
            manifest.repository.url =
                    "https://github.com/cozy/cozy-#{name}.git"
            manifest.name = name
            manifest.user = name
            log.info "Restart started for #{name}..."
            client.stop manifest, (err, res, body) ->
                client.start manifest, (err, res, body)  ->
                    if err or body.error?
                        handleError err, body, "Start failed"
                    else
                        client.brunch manifest, =>
                            log.info "#{name} successfully started"
                            callback null

        restartApp 'data-system', () =>
            restartApp 'home', () =>
                restartApp 'proxy', () =>
                    log.info 'Cozy stack successfully restarted'


# Brunch

program
    .command("brunch <app>")
    .description("Build brunch client for given application.")
    .action (app) ->
        log.info "Brunch build #{app}..."
        manifest.name = app
        manifest.repository.url =
            "https ://github.com/cozy/cozy-#{app}.git"
        manifest.user = app
        client.brunch manifest, (err, res, body) ->
            if err or body.error?
                handleError err, body, "Brunch build failed"
            else
                log.info "#{app} client successfully built."


# Update

program
    .command("update <app> [repo]")
    .description(
        "Update application (git + npm) and restart it. Option repo " +
        "is usefull only if app comes from a specific repo")
    .action (app, repo) ->
        log.info "Update #{app}..."
        if app in ['data-system', 'home', 'proxy']
            manifest.name = app
            if repo?
                manifest.repository.url = repo
            else
                manifest.repository.url =
                    "https ://github.com/cozy/cozy-#{app}.git"
            manifest.user = app
            client.lightUpdate manifest, (err, res, body) ->
                if err or body.error?
                    handleError err, body, "Update failed"
                else
                    log.info "#{app} successfully updated"
        else
            find = false
            homeClient.get "api/applications/", (err, res, apps) ->
                if apps? and apps.rows?
                    for manifest in apps.rows
                        if manifest.name is app
                            find = true
                            path = "api/applications/#{manifest.slug}/update"
                            homeClient.put path, manifest, (err, res, body) ->
                                if err or body.error
                                    handleError err, body, "Update failed"
                                else
                                    log.info "#{app} successfully updated"
                    if not find
                        log.error "Update failed : application #{app} not found"
                else
                    log.error "Update failed : no applications installed"


program
    .command("update-cozy-stack")
    .description(
        "Update application (git + npm) and restart it through controller")
    .action () ->
        lightUpdateApp = (name, callback) ->
            manifest.repository.url =
                    "https://github.com/cozy/cozy-#{name}.git"
            manifest.name = name
            manifest.user = name
            log.info "Light update #{name}..."
            client.lightUpdate manifest, (err, res, body) ->
                if err or body.error?
                    handleError err, body, "Start failed"
                else
                    client.brunch manifest, =>
                        log.info "#{name} successfully updated"
                        callback null

        lightUpdateApp 'data-system', () =>
            lightUpdateApp 'home', () =>
                lightUpdateApp 'proxy', () =>
                    log.info 'Cozy stack successfully updated'


program
    .command("update-all")
    .description("Reinstall all user applications")
    .action ->
        startApp = (app, callback) ->
            path = "api/applications/#{app.slug}/start"
            homeClient.post path, app, (err, res, body) ->
                if err or body.error
                    callback(err)
                else
                    callback()

        removeApp = (app, callback) ->
            path = "api/applications/#{app.slug}/uninstall"
            homeClient.del path, (err, res, body) ->
                if err or body.error
                    callback(err)
                else
                    callback()

        installApp = (app, callback) ->
            path = "api/applications/install"
            homeClient.post path, app, (err, res, body) ->
                waitInstallComplete app.slug, (err, appresult) ->
                    if err or body.error
                        callback(err)
                    else
                        callback()

        stopApp = (app, callback) ->
            path = "api/applications/#{app.slug}/stop"
            homeClient.post path, app, (err, res, body) ->
                if err or body.error
                    callback(err)
                else
                    callback()

        lightUpdateApp = (app, callback) ->
            path = "api/applications/#{app.slug}/update"
            homeClient.put path, app, (err, res, body) ->
                if err or body.error
                    callback(err)
                else
                    callback()

        endUpdate = (app, callback) ->
            path = "api/applications/byid/#{app.id}"
            homeClient.get path, (err, res, app) ->
                if app.state is "installed"
                    log.info " * New status: " + "started".bold
                else
                    log.info " * New status: " + app.state.bold
                log.info app.name + " updated"
                callback()

        updateApp = (app) ->
            (callback) ->
                log.info "\nStarting update #{app.name}..."
                # When application is broken, try :
                #   * remove application
                #   * install application
                #   * stop application
                if app.state is 'broken'
                    log.info " * Old status: " + "broken".bold

                    log.info " * Remove #{app.name}"
                    removeApp app, (err) ->
                        if err
                            log.error 'An error occured: '
                            log.raw err

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
                else if app.state is 'installed'
                    log.info " * Old status: " + "started".bold
                    log.info " * Update " + app.name
                    lightUpdateApp app, (err) ->
                        if err
                            log.error 'An error occured:'
                            log.raw err
                        endUpdate app, callback

                # When application is stopped, try :
                #   * start application
                #   * update application
                #   * stop application
                else
                    log.info " * Old status: " + "stopped".bold
                    log.info " * Start " + app.name
                    startApp app, (err) ->
                        if err
                            log.error 'An error occured:'
                            log.raw err
                            endUpdate app, callback
                        else
                            log.info " * Update " + app.name
                            lightUpdateApp app, (err) ->
                                if err
                                    log.error 'An error occured:'
                                    log.raw err
                                log.info " * Stop " + app.name
                                stopApp app, (err) ->
                                    if err
                                        log.error 'An error occured:'
                                        log.raw err
                                    endUpdate app, callback

        homeClient.host = homeUrl
        homeClient.get "api/applications/", (err, res, apps) ->
            funcs = []
            if apps? and apps.rows?
                for app in apps.rows
                    func = updateApp(app)
                    funcs.push func

                async.series funcs, ->
                    log.info "\nAll apps reinstalled."
                    log.info "Reset proxy routes"

                    statusClient.host = proxyUrl
                    statusClient.get "routes/reset", (err, res, body) ->
                        if err
                            handleError err, body, "Cannot reset routes."
                        else
                            log.info "Reset proxy succeeded."


# Versions


program
    .command("versions-stack")
    .description("Display stack applications versions")
    .action () ->
        log.raw('Cozy Stack:'.bold)
        getVersion("controller")
        getVersion("data-system")
        getVersion("home")
        getVersion('proxy')
        getVersionIndexer (indexerVersion) =>
            log.raw "indexer: #{indexerVersion}"
            log.raw "monitor: #{version}"


program
    .command("versions")
    .description("Display applications versions")
    .action () ->
        log.raw('Cozy Stack:'.bold)
        getVersion("controller")
        getVersion("data-system")
        getVersion("home")
        getVersion('proxy')
        getVersionIndexer (indexerVersion) =>
            log.raw "indexer: #{indexerVersion}"
            log.raw "monitor: #{version}"
            log.raw("Other applications: ".bold)
            homeClient.host = homeUrl
            homeClient.get "api/applications/", (err, res, apps) ->
                if apps? and apps.rows?
                    for app in apps.rows
                        log.raw "#{app.name}: #{app.version}"


## Monitoring ###


program
    .command("dev-route:start <slug> <port>")
    .description("Create a route so we can access it by the proxy. ")
    .action (slug, port) ->
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
                        log.info "route created"
                        log.info "start your app with the following ENV"
                        log.info "NAME=#{slug} TOKEN=#{slug} PORT=#{port}"
                        log.info "Use dev-route:stop #{slug} to remove it."


program
    .command("dev-route:stop <slug>")
    .action (slug) ->
        client = request.newClient dataSystemUrl
        client.setBasicAuth 'home', token if token = getToken()
        appsQuery = 'request/application/all/'

        client.post appsQuery, null, (err, res, apps) ->
            if err or not apps?
                handleError err, apps, "Unable to retrieve apps data."
            else
                for app in apps
                    isSlug = (app.key is slug or slug is 'all')
                    if isSlug and app.value.devRoute
                        delQuery = "data/#{app.id}/"
                        client.del delQuery, (err, res, body) ->
                            if err
                                handleError(
                                    err, body, "Unable to delete route.")
                            else
                                log.info "Route deleted"
                                client.host = proxyUrl
                                client.get 'routes/reset', (err, res, body) ->
                                    if err
                                        handleError err, body, \
                                            "Reset routes failed"
                                    else
                                        log.info "Proxy routes reset"
                        return

            console.log "There is no dev route with this slug"


program
    .command("routes")
    .description("Display routes currently configured inside proxy.")
    .action ->
        log.info "Display proxy routes..."

        statusClient.host = proxyUrl
        statusClient.get "routes", (err, res, routes) ->

            if err
                handleError err, {}, "Cannot display routes."
            else if routes?
                for route of routes
                    log.raw "#{route} => #{routes[route].port}"


program
    .command("module-status <module>")
    .description("Give status of given in an easy to parse way.")
    .action (module) ->
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


program
    .command("status")
    .description("Give current state of cozy platform applications")
    .action ->
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


program
    .command("log <app> <type>")
    .description("Display application log with cat or tail -f")
    .action (app, type, environment) ->
        path = "/usr/local/var/log/cozy/#{app}.log"
        if not fs.existsSync(path)
            log.error "Log file doesn't exist"
        else
            if type is "cat"
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


## Database ##

program
    .command("compact [database]")
    .description("Start couchdb compaction")
    .action (database) ->
        if not database?
            database = "cozy"
        log.info "Start couchdb compaction on #{database} ..."
        client = request.newClient couchUrl
        getAuthCouchdb (err, username, password) ->
            if err
                process.exit 1
            else
                client.setBasicAuth username, password
                client.post "#{database}/_compact", {}, (err, res, body) ->
                    if err
                        handleError err, body, "Compaction failed."
                    else if not body.ok
                        handleError err, body, "Compaction failed."
                    else
                        waitCompactComplete client, false, (success) =>
                            log.info "#{database} compaction succeeded"
                            process.exit 0


program
    .command("compact-views <view> [database]")
    .description("Start couchdb compaction")
    .action (view, database) ->
        if not database?
            database = "cozy"
        log.info "Start vews compaction on #{database} for #{view} ..."
        compactViews database, view, (err) =>
            if not err
                log.info "#{database} compaction for #{view}" +
                            " succeeded"
                process.exit 0


program
    .command("compact-all-views [database]")
    .description("Start couchdb compaction")
    .action (database) ->
        if not database?
            database = "cozy"
        log.info "Start vews compaction on #{database} ..."
        client = request.newClient couchUrl
        getAuthCouchdb (err, username, password) ->
            if err
                process.exit 1
            else
                client.setBasicAuth username, password
                path = "#{database}/_all_docs?startkey=\"_design/\"&endkey=" +
                    "\"_design0\"&include_docs=true"
                client.get path, (err, res, body) =>
                    if err
                        handleError err, body, "Views compaction failed. " +
                            "Cannot recover all design documents"
                    else
                        designs = []
                        (body.rows).forEach (design) ->
                            designId = design.id
                            designDoc = designId.substring 8, designId.length
                            designs.push designDoc
                        compactAllViews database, designs, (err) =>
                            if not err
                                log.info "Views are successfully compacted"


program
    .command("cleanup [database]")
    .description("Start couchdb cleanup")
    .action (database) ->
        if not database?
            database = "cozy"
        log.info "Start couchdb cleanup on #{database} ..."
        client = request.newClient couchUrl
        getAuthCouchdb (err, username, password) ->
            if err
                process.exit 1
            else
                client.setBasicAuth username, password
                path = "#{database}/_view_cleanup"
                client.post path, {}, (err, res, body) ->
                    if err
                        handleError err, body, "Cleanup failed."
                    else if not body.ok
                        handleError err, body, "Cleanup failed."
                    else
                        log.info "#{database} cleanup succeeded"
                        process.exit 0

## Backup ##

program
    .command("backup <target>")
    .description("Start couchdb replication to the target")
    .action (target) ->
        client = request.newClient couchUrl
        data =
            source: "cozy"
            target: target
        getAuthCouchdb (err, username, password) ->
            if err
                process.exit 1
            else
                client.setBasicAuth username, password
                client.post "_replicate", data, (err, res, body) ->
                    if err
                        handleError err, body, "Backup failed."
                    else if not body.ok
                        handleError err, body, "Backup failed."
                    else
                        log.info "Backup succeeded"
                        process.exit 0


program
    .command("reverse-backup <backup> <username> <password>")
    .description("Start couchdb replication from target to cozy")
    .action (backup, usernameBackup, passwordBackup) ->
        log.info "Reverse backup..."
        client = request.newClient couchUrl
        getAuthCouchdb (err, username, password) ->
            if err
                process.exit 1
            else
                prepareCozyDatabase username, password, () ->
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
                    client.post "_replicate", data, (err, res, body) ->
                        if err
                            handleError err, body, "Backup failed."
                        else if not body.ok
                           handleError err, body, "Backup failed."
                        else
                            log.info "Reverse backup succeeded"
                            process.exit 0

## Others ##

program
    .command("script <app> <script> [argument]")
    .description("Launch script that comes with given application")
    .action (app, script, argument) ->
        argument ?= ''

        log.info "Run script #{script} for #{app}..."
        path = "/usr/local/cozy/apps/#{app}/"
        exec "cd #{path}; compound database #{script} #{argument}", \
                     (err, stdout, stderr) ->
            log.info stdout
            if err
                handleError err, stdout, "Script execution failed"
            else
                log.info "Command successfully applied."


program
    .command("reset-proxy")
    .description("Reset proxy routes list of applications given by home.")
    .action ->
        log.info "Reset proxy routes"

        statusClient.host = proxyUrl
        statusClient.get "routes/reset", (err, res, body) ->
            if err
                handleError err, body, "Reset routes failed"
            else
                log.info "Reset proxy succeeded."


program
    .command("*")
    .description("Display error message for an unknown command.")
    .action ->
        log.error 'Unknown command, run "cozy-monitor --help"' + \
                    ' to know the list of available commands.'

program.parse process.argv

unless process.argv.slice(2).length
    program.outputHelp()


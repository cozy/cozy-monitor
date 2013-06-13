# This program is suited only to manage your cozy installation from the inside
# Moreover app management works only for apps make by Cozy Cloud company.
# If you want a friendly application manager you should use the
# appmanager.coffee script.

require "colors"

program = require 'commander'
async = require "async"
fs = require "fs"
exec = require('child_process').exec

Client = require("request-json").JsonClient
ControllerClient = require("cozy-clients").ControllerClient
redis = require 'redis'

couchUrl = "http://localhost:5984/"
dataSystemUrl = "http://localhost:9101/"
indexerUrl = "http://localhost:9102/"
controllerUrl = "http://localhost:9002/"
homeUrl = "http://localhost:9103/"
proxyUrl = "http://localhost:9104/"

homeClient = new Client homeUrl
statusClient = new Client ''



## Helpers

getToken = () ->
    if fs.existsSync '/etc/cozy/controller.token'
        try
            token = fs.readFileSync '/etc/cozy/controller.token', 'utf8'
            token = token.split('\n')[0]
            return token
        catch err
            console.log("Are you sure, you are root ?")
    else
        return null


getAuthCouchdb = (callback) ->
    fs.readFile '/etc/cozy/couchdb.login', 'utf8', (err, data) =>
        if err
            console.log "Cannot read login in /etc/cozy/couchdb.login"
            callback err
        else
            username = data.split('\n')[0]
            password = data.split('\n')[1]
            callback null, username, password


handleError = (err, body, msg) ->
    console.log err if err
    console.log msg
    if body?
        if body.msg?
           console.log body.msg
        else console.log body
    process.exit 1


compact_views = (database, design_doc, callback) ->
    client = new Client couchUrl
    getAuthCouchdb (err, username, password) ->
        if err
            process.exit 1
        else
            client.setBasicAuth username, password
            path = "#{database}/_compact/#{design_doc}"
            client.post path, {}, (err, res, body) =>
                if err
                    handleError err, body, "compaction failed for #{design_doc}"
                else if not body.ok
                    handleError err, body, "compaction failed for #{design_doc}"
                else
                    callback null


compact_all_views = (database, designs, callback) ->
    if designs.length > 0
        design = designs.pop()
        console.log("views compaction for #{design}")
        compact_views database, design, (err) =>
            compact_all_views database, designs, callback
    else
        callback null


token = getToken()
client = new ControllerClient
    token: token

manifest =
   "domain": "localhost"
   "repository":
       "type": "git",
   "scripts":
       "start": "server.coffee"


program
  .version('1.0.4')
  .usage('<action> <app>')


program
    .command("install <app>")
    .description("Install application in controller")
    .action (app) ->
        manifest.name = app
        manifest.repository.url =
            "https://github.com/mycozycloud/cozy-#{app}.git"
        manifest.user = app
        console.log "Install started for #{app}..."
        client.clean manifest, (err, res, body) ->
            client.start manifest, (err, res, body)  ->
                if err or body.error?
                    handleError err, body, "Install failed"
                else
                    client.brunch manifest, =>
                        console.log "#{app} successfully installed"

program
    .command("install_home <app>")
    .description("Install application via home app")
    .action (app) ->
        manifest.name = app
        manifest.git =
            "https://github.com/mycozycloud/cozy-#{app}.git"
        manifest.user = app
        console.log "Install started for #{app}..."
        path = "api/applications/install"
        homeClient.post path, manifest, (err, res, body) ->
            if err or body.error
                handleError err, body, "Install home failed"
            else
                console.log "install started"
                clientRedis = redis.createClient()
                clientRedis.psubscribe 'application.update'
                timeoutId = setTimeout () =>
                    clientRedis.quit()
                    statusClient.host = body.host
                    statusClient.get "api/applications/", (err, res) ->
                        if not res? or
                        (res.statusCode isnt 200 and res.statusCode isnt 403)
                            console.log "Install failed"
                        else
                            console.log "#{app} successfully installed"
                , 240000
                clientRedis.on 'pmessage', (pat, ch, msg) =>
                    dSclient = new Client dataSystemUrl
                    dSclient.get "data/#{msg}/", (err, response, body) =>
                        clientRedis.quit()
                        if not err? and body.state is "installed"
                            console.log "#{app} successfully installed"
                        else
                            handleError null, null, "Install home failed"


program
    .command("uninstall_home <app>")
    .description("Install application via home app")
    .action (app) ->
        console.log "Uninstall started for #{app}..."
        path = "api/applications/#{app}/uninstall"
        homeClient.del path, (err, res, body) ->
            if err or res.statusCode isnt 200
                handleError err, body, "Uninstall home failed"
            else
                console.log "#{app} successfully uninstalled"


program
    .command("uninstall <app>")
    .description("Remove application from controller")
    .action (app) ->
        manifest.name = app
        manifest.user = app
        console.log "Uninstall started for #{app}..."

        client.clean manifest, (err, res, body) ->
            if err or body.error?
                handleError err, body, "Uninstall failed"
            else
                console.log "#{app} successfully uninstalled"


program
    .command("start <app>")
    .description("Start application through controller")
    .action (app) ->
        manifest.name = app
        manifest.repository.url =
            "https://github.com/mycozycloud/cozy-#{app}.git"
        manifest.user = app
        console.log "Starting #{app}..."
        client.stop app, (err, res, body) ->
            client.start manifest, (err, res, body) ->
                if err or body.error?
                    handleError err, body, "Start failed"
                else
                    console.log "#{app} successfully started"


program
    .command("stop <app>")
    .description("Stop application through controller")
    .action (app) ->
        console.log "Stopping #{app}..."
        manifest.name = app
        manifest.user = app
        client.stop app, (err, res, body) ->
            if err or body.error?
                handleError err, body, "Stop failed"
            else
                console.log "#{app} successfully stopped"


program
    .command("brunch <app>")
    .description("Build brunch client for given application.")
    .action (app) ->
        console.log "Brunch build #{app}..."
        manifest.name = app
        manifest.repository.url =
            "https ://github.com/mycozycloud/cozy-#{app}.git"
        manifest.user = app
        client.brunch manifest, (err, res, body) ->
            if err or body.error?
                handleError err, body, "Brunch build failed"
            else
                console.log "#{app} client successfully built."


program
    .command("restart <app>")
    .description("Restart application trough controller")
    .action (app) ->
        console.log "Stopping #{app}..."
        manifest.name = app
        manifest.repository.url =
            "https://github.com/mycozycloud/cozy-#{app}.git"
        manifest.user = app
        client.stop app, (err, res, body) ->
            if err or body.error?
                handleError err, body, "Stop failed"
            else
                console.log "#{app} successfully stopped"
                console.log "Starting #{app}..."
                client.start manifest, (err, res, body) ->
                    if err
                        handleError err, body, "Start failed"
                    else
                        console.log "#{app} sucessfully started"


program
    .command("light-update <app>")
    .description(
        "Update application (git + npm) and restart it through controller")
    .action (app) ->
        console.log "Light update #{app}..."
        manifest.name = app
        manifest.repository.url =
            "https ://github.com/mycozycloud/cozy-#{app}.git"
        manifest.user = app
        client.lightUpdate manifest, (err, res, body) ->
            if err or body.error?
                handleError err, body, "Light update failed"
            else
                client.brunch manifest, ->
                    console.log "#{app} successfully updated"


program
    .command("uninstall-all")
    .description("Uninstall all apps from controller")
    .action (app) ->
        console.log "Uninstall all apps..."

        client.cleanAll (err, res, body) ->
            if err  or body.error?
                handleError err, body, "Uninstall all failed"
            else
                console.log "All apps successfully uinstalled"


program
    .command("script <app> <script> [argument]")
    .description("Launch script that comes with given application")
    .action (app, script, argument) ->
        argument ?= ''

        console.log "Run script #{script} for #{app}..."
        path = "/usr/local/cozy/apps/#{app}/#{app}/cozy-#{app}/"
        exec "cd #{path}; compound database #{script} #{argument}", \
                     (err, stdout, stderr) ->
            console.log stdout
            if err
                handleError err, stdout, "Script execution failed"
            else
                console.log "Command successfully applied."


program
    .command("reset-proxy")
    .description("Reset proxy routes list of applications given by home.")
    .action ->
        console.log "Reset proxy routes"

        statusClient.host = proxyUrl
        statusClient.get "routes/reset", (err, res, body) ->
            if err
                handleError err, body, "Reset routes failed"
            else
                console.log "Reset proxy succeeded."


program
    .command("dev-route:start <slug> <port>")
    .description("Create a route so we can access it by the proxy. ")
    .action (slug, port) ->
        client = new Client dataSystemUrl
        data =
            docType: "Application"
            status: "installed"
            slug: slug
            name: slug
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
                        console.log "route created"
                        console.log "start your app on port #{port}"
                        console.log "Use dev-route:stop #{slug} to remove it."


program
    .command("dev-route:stop <slug>")
    .action (slug) ->
        client = new Client dataSystemUrl
        appsQuery = 'request/application/all/'

        client.post appsQuery, null, (err, res, apps) ->
            if err or not apps?
                handleError err, apps, "Unable to retrieve apps data."
            else
                for app in apps
                    if (app.key is slug or slug is 'all') and app.value.devRoute
                        delQuery = "data/#{app.id}/"
                        client.del delQuery, (err, res, body) ->
                            if err
                                handleError err, body, "Unable to delete route."
                            else
                                console.log "Route deleted"
                                client.host = proxyUrl
                                client.get 'routes/reset', (err, res, body) ->
                                    if err
                                        handleError err, body, \
                                            "Reset routes failed"
                                    else
                                        console.log "Proxy routes reset"
                        return

            console.log "There is no dev route with this slug"


program
    .command("routes")
    .description("Display routes currently configured inside proxy.")
    .action ->
        console.log "Display proxy routes..."

        statusClient.host = proxyUrl
        statusClient.get "routes", (err, res, routes) ->

            if err
                handleError err, body, "Cannot display routes."
            else if routes?
                for route of routes
                    console.log "#{route} => #{routes[route]}"


program
    .command("status")
    .description("Give current state of cozy platform applications")
    .action ->
        checkApp = (app, host, path="") ->
            (callback) ->
                statusClient.host = host
                statusClient.get path, (err, res) ->
                    if not res? or
                    (res.statusCode isnt 200 and res.statusCode isnt 403)

                        console.log "#{app}: " + "down".red
                    else
                        console.log "#{app}: " + "up".green
                    callback()
                , false

        async.series [
            checkApp("controller", controllerUrl, "version")
            checkApp("data-system", dataSystemUrl)
            checkApp("indexer", indexerUrl)
            checkApp("home", homeUrl)
            checkApp("proxy", proxyUrl, "routes")
        ], ->
            statusClient.host = homeUrl
            statusClient.get "api/applications/", (err, res, apps) ->
                funcs = []
                if apps? and apps.rows?
                    for app in apps.rows
                        func = checkApp(app.name, "http://localhost:#{app.port}/")
                        funcs.push func
                    async.series funcs, ->


program
    .command("reinstall-all")
    .description("Reinstall all user applications")
    .action ->
        installApp = (app) ->
            (callback) ->
                console.log "Install started for #{app.name}..."
                manifest.name = app.name
                manifest.repository.url = app.git
                manifest.user = app.name

                client.clean manifest, (err, body) ->
                    client.start manifest, (err, body) ->
                        if err
                            console.log "Install failed"
                            console.log err if err
                            if res?.body?
                                if res.body.msg?
                                    console.log res.body.msg
                                else
                                    console.log res.body
                            callback()
                        else
                            client.brunch manifest, ->
                                console.log "#{app.name} successfully installed"
                                callback()

        statusClient.host = homeUrl
        statusClient.get "api/applications/", (err, res, apps) ->
            funcs = []
            if apps? and apps.rows?
                for app in apps.rows
                    func = installApp(app)
                    funcs.push func

                async.series funcs, ->
                    console.log "All apps reinstalled."
                    console.log "Reset proxy routes"

                    statusClient.host = proxyUrl
                    statusClient.get "routes/reset", (err, res, body) ->
                        if err
                            handleError err, body, "Cannot reset routes."
                        else
                            console.log "Reset proxy succeeded."


program
    .command("compact <database>")
    .description("Start couchdb compaction")
    .action (database) ->
        console.log "Start couchdb compaction on #{database} ..."
        client = new Client couchUrl
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
                        console.log "#{database} compaction succeeded"
                        process.exit 0


program
    .command("compact-views <database> <design_doc>")
    .description("Start couchdb compaction")
    .action (database, design_doc) ->
        console.log "Start vews compaction on #{database} for #{design_doc} ..."
        compact_views database, design_doc, (err) =>
            if not err
                console.log "#{database} compaction for #{design_doc}" +
                            " succeeded"
                process.exit 0

program
    .command("compact-all-views <database>")
    .description("Start couchdb compaction")
    .action (database) ->
        console.log "Start vews compaction on #{database} ..."
        client = new Client couchUrl
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
                            design_id = design.id
                            design_doc = design_id.substring 8, design_id.length
                            designs.push design_doc
                        compact_all_views database, designs, (err) =>
                            if not err
                                console.log "Views are successfully compacted"


program
    .command("cleanup <database>")
    .description("Start couchdb cleanup")
    .action (database) ->
        console.log "Start couchdb cleanup on #{database} ..."
        client = new Client couchUrl
        getAuthCouchdb (err, username, password) ->
            if err
                process.exit 1
            else
                client.setBasicAuth username, password
                client.post "#{database}/_view_cleanup", {}, (err, res, body) ->
                    if err
                        handleError err, body, "Cleanup failed."
                    else if not body.ok
                        handleError err, body, "Cleanup failed."
                    else
                        console.log "#{database} cleanup succeeded"
                        process.exit 0


program
    .command("backup <target>")
    .description("Start couchdb replication to the target")
    .action (target) ->
        client = new Client couchUrl
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
                        console.log "Backup succeeded"
                        process.exit 0


program
    .command("*")
    .description("Display error message for an unknown command.")
    .action ->
        console.log 'Unknown command, run "cozy-monitor --help"' + \
                    ' to know the list of available commands.'

program.parse process.argv

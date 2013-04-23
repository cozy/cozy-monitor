# This program is suited only to manage your cozy installation from the inside
# Moreover app management works only for apps make by Cozy Cloud company.
# If you want a friendly application manager you should use the
# appmanager.coffee script.

require "colors"

program = require 'commander'
async = require "async"
exec = require('child_process').exec

haibu = require('haibu-api')
Client = require("request-json").JsonClient


couchUrl = "http://localhost:5984/"
controllerUrl = "http://localhost:9002/"

dataSystemUrl = "http://localhost:9101/"
indexerUrl = "http://localhost:9102/"
homeUrl = "http://localhost:9103/"
proxyUrl = "http://localhost:9104/"

homeClient = new Client homeUrl
controllerClient = new Client controllerUrl
statusClient = new Client ''

client = haibu.createClient
  host: 'localhost'
  port: 9002
client = client.drone

client.brunch = (manifest, callback) ->
    data = brunch: manifest
    controllerClient.post "drones/#{manifest.name}/brunch", data, callback

manifest =
   "domain": "localhost"
   "repository":
       "type": "git",
   "scripts":
       "start": "server.coffee"

program
  .version('0.0.1')
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

        client.clean manifest, (err, result) ->
            client.start manifest, (err, result) ->
                if err
                    console.log err
                    console.log "Install failed"
                else
                    client.brunch manifest, ->
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
            if err or res.statusCode isnt 200
                console.log err if err?
                console.log "Install failed"
                if body?
                    if body.msg? then console.log body.msg else console.log body
            else
                console.log "#{app} successfully installed"

program
    .command("uninstall_home <app>")
    .description("Install application via home app")
    .action (app) ->
        console.log "Uninstall started for #{app}..."
        path = "api/applications/#{app}/uninstall"
        homeClient.del path, (err, res, body) ->
            if err or res.statusCode isnt 200
                console.log err if err?
                console.log "Uninstall failed"
                if body?
                    if body.msg? then console.log body.msg else console.log body
            else
                console.log "#{app} successfully uninstalled"

program
    .command("uninstall <app>")
    .description("Remove application from controller")
    .action (app) ->
        manifest.name = app
        manifest.user = app
        console.log "Uninstall started for #{app}..."

        client.clean manifest, (err, result) ->
            if err
                console.log "Uninstall failed"
                console.log err
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
        client.stop app, (err, result) ->
            client.start manifest, (err, result) ->
                if err
                    console.log "Start failed"
                    console.log err
                else
                    console.log "#{app} successfully started"

program
    .command("stop <app>")
    .description("Stop application through controller")
    .action (app) ->
        console.log "Stopping #{app}..."
        app.user = app
        client.stop app, (err) ->
            if err
                console.log "Stop failed"
                console.log err.result.error.message
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
            if res.statusCode isnt 200
                console.log "Brunch build failed."
                console.log body
            else
                console.log "#{app} client successfully built."

program
    .command("restart <app>")
    .description("Restart application trough controller")
    .action (app) ->
        console.log "Stopping #{app}..."

        client.stop app, (err) ->
            if err
                console.log "Stop failed"
                console.log err.result.error.message
            else
                console.log "#{app} successfully stopped"
                manifest.name = app
                manifest.repository.url =
                    "https://github.com/mycozycloud/cozy-#{app}.git"
                manifest.user = app
                console.log "Starting #{app}..."

                client.start manifest, (err, result) ->
                if err
                    console.log "Start failed"
                    console.log err
                else
                    console.log "#{app} successfully started"

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

        controllerClient.post "drones/#{app}/light-update", \
             {update : manifest}, (err, res, body) ->
            if (res.statusCode isnt 200)
                console.log "Update failed"
                console.log body
            else
                client.brunch manifest, ->
                    console.log "#{app} successfully updated"

program
    .command("uninstall-all")
    .description("Uninstall all apps from controller")
    .action (app) ->
        console.log "Uninstall all apps..."

        client.cleanAll (err) ->
            if err
                console.log "Uninstall all failed"
                console.log err.result.error.message
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
                console.log "exec error: #{err}"
                console.log "stderr: #{stderr}"

program
    .command("reset-proxy")
    .description("Reset proxy routes list of applications given by home.")
    .action ->
        console.log "Reset proxy routes"

        statusClient.host = proxyUrl
        statusClient.get "routes/reset", (err) ->
            if err
                console.log err
                console.log "Reset proxy failed."
            else
                console.log "Reset proxy succeeded."

program
    .command("routes")
    .description("Display routes currently configured inside proxy.")
    .action ->
        console.log "Display proxy routes..."

        statusClient.host = proxyUrl
        statusClient.get "routes", (err, res, routes) ->

            if not err and routes?
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
                    if res.statusCode isnt 200
                        console.log "#{app}: " + "down".red
                    else
                        console.log "#{app}: " + "up".green
                    callback()

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

                client.clean manifest, (err, result) ->
                    client.start manifest, (err, result) ->
                        if err
                            console.log err
                            console.log "Install failed"
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
                    statusClient.get "routes/reset", (err) ->
                        if err
                            console.log err
                            console.log "Reset proxy failed."
                        else
                            console.log "Reset proxy succeeded."

program
    .command("backup <target>")
    .description("Start couchdb replication to the target")
    .action (target) ->
        client = new Client couchUrl
        data =
            source: "cozy"
            target: target
        client.post "_replicate", data, (err, res, body) ->
            if err
                console.log err
                console.log "Backup Not Started"
                process.exit 1
            else if not body.ok
                console.log body
                console.log "Backup start but failed"
                process.exit 1
            else
                console.log "Backup succeed"
                process.exit 0

program
    .command("*")
    .description("Display error message for an unknown command.")
    .action ->
        console.log 'Unknown command, run "cozy-monitor --help"' + \
                    ' to know the list of available commands.'

program.parse(process.argv)

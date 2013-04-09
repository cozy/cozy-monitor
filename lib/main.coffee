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


homeUrl = "http://localhost:9103/"
proxyUrl = "http://localhost:9104/"
couchUrl = "http://localhost:5984/"
haibuUrl = "http://localhost:9002/"
homeClient = new Client homeUrl
controllerClient = new Client haibuUrl
statusClient = new Client ''

client = haibu.createClient
  host: 'localhost'
  port: 9002
client = client.drone


client.clean = (manifest, token, callback) ->
    data = manifest
    controllerClient.setToken token
    controllerClient.post "drones/#{manifest.name}/clean", data, callback

client.cleanAll = (token, callback) ->
    controllerClient.setToken token
    controllerClient.post "drones/cleanAll", callback

client.stop = (manifest, token, callback) ->
    data =
        stop:
            name: manifest
    controllerClient.setToken token
    controllerClient.post "drones/#{manifest.name}/stop", data, callback

client.start = (manifest, token, callback) ->
    data = start: manifest
    controllerClient.setToken token
    controllerClient.post "drones/#{manifest.name}/start", data, callback

client.brunch = (manifest, token, callback) ->
    data = brunch: manifest
    controllerClient.setToken token
    controllerClient.post "drones/#{manifest.name}/brunch", data, callback

client.lightUpdate = (manifest, token, callback) ->
    data = update: manifest
    controllerClient.setToken token
    controllerClient.post "drones/#{manifest.name}/light-update", data, callback

client.token = (token, callback) ->
    controllerClient.setToken token
    data = token: token
    controllerClient.post "authToken", data,  callback



manifest =
   "domain": "localhost"
   "repository":
       "type": "git",
   "scripts":
       "start": "server.coffee"

program
  .version('0.0.1')
  .usage('<action> <app> <token>')


program
    .command("token <token>")
    .description("Add authenticate Token")
    .action (token) ->
        client.token token, (err, res, body) ->
            if err or res.statusCode isnt 200
                console.log err if err?
                console.log "AuthToken failed"
                if body?
                    if body.msg? then console.log body.msg else console.log body
            else
                console.log "token sucessfully added"

program
    .command("install <app> <token>")
    .description("Install application in haibu")
    .action (app, token) ->
        manifest.name = app
        manifest.repository.url =
            "https://github.com/mycozycloud/cozy-#{app}.git"
        manifest.user = app
        console.log "Install started for #{app}..."

        client.clean manifest, token, (err, res, body) ->
            client.start manifest, token, (err, res, body)  ->
                if err or res.statusCode isnt 200
                    console.log err if err
                    console.log "Install failed"
                    if res.body?
                        if res.body.msg? then console.log res.body.msg else console.log res.body
                else
                    client.brunch manifest, token, ->
                        console.log "#{app} sucessfully installed"

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
                console.log "#{app} sucessfully installed"

program
    .command("uninstall_home <app>")
    .description("Install application via home app")
    .action (app) ->
        console.log "Uninstall started for #{app}..."
        path = "api/applications/#{app}/uninstall"
        homeClient.del path, (err, res, body) ->
            if err or res.statusCode isnt 200
                console.log err if err
                console.log "Uninstall failed"
                if body?
                    if body.msg? then console.log body.msg else console.log body
            else
                console.log "#{app} sucessfully uninstalled"

program
    .command("uninstall <app> <token>")
    .description("Remove application from haibu")
    .action (app, token) ->
        manifest.name = app
        manifest.user = app
        console.log "Uninstall started for #{app}..."

        client.clean manifest, token, (err, res, body) ->
            console.log res
            if err or res.statusCode isnt 200
                console.log "Uninstall failed"
                console.log err if err
                if body?
                    if body.msg? then console.log body.msg else console.log body
            else
                console.log "#{app} sucessfully uninstalled"

program
    .command("start <app> <token>")
    .description("Start application through haibu")
    .action (app, token) ->
        manifest.name = app
        manifest.repository.url =
            "https://github.com/mycozycloud/cozy-#{app}.git"
        manifest.user = app
        console.log "Starting #{app}..."

        client.start manifest, token, (err, res, body) ->
            if err or res.statusCode isnt 200
                console.log "Start failed"
                console.log err if err
                if res.body?
                    if res.body.msg? then console.log res.body.msg else console.log res.body
            else
                console.log "#{app} sucessfully started"

program
    .command("stop <app> <token>")
    .description("Stop application through haibu")
    .action (app, token) ->
        console.log "Stopping #{app}..."
        app.user = app
        client.stop app, token, (err, res) ->
            if err or res.statusCode isnt 200
                console.log "Stop failed"
                console.log err if err
                if res.body?
                    if res.body.msg? then console.log res.body.msg else console.log res.body
            else
                console.log "#{app} sucessfully stopped"

program
    .command("brunch <app> <token>")
    .description("Build brunch client for given application.")
    .action (app, token) ->
        console.log "Brunch build #{app}..."
        manifest.name = app
        manifest.repository.url =
            "https ://github.com/mycozycloud/cozy-#{app}.git"
        manifest.user = app
        client.brunch manifest, token, (err, res, body) ->
            if err or res.statusCode isnt 200
                console.log "Brunch build failed."
                console.log err if err
                if res.body?
                    if res.body.msg? then console.log res.body.msg else console.log res.body
            else
                console.log "#{app} client sucessfully built."

program
    .command("restart <app> <token>")
    .description("Restart application trough haibu")
    .action (app, token) ->
        console.log "Stopping #{app}..."

        client.stop app, token, (err, res) ->
            if err or res.statusCode isnt 200
                console.log "Stop failed"
                console.log err if err
                if res.body?
                    if res.body.msg? then console.log res.body.msg else console.log res.body
            else
                console.log "#{app} sucessfully stopped"
                manifest.name = app
                manifest.repository.url =
                    "https://github.com/mycozycloud/cozy-#{app}.git"
                manifest.user = app
                console.log "Starting #{app}..."

                client.start manifest, token, (err, res, body) ->
                if err or res.statusCode isnt 200
                    console.log "Start failed"
                    console.log err
                else
                    console.log "#{app} sucessfully started"

program
    .command("light-update <app> <token>")
    .description(
        "Update application (git + npm install) and restart it through haibu")
    .action (app, token) ->
        console.log "Light update #{app}..."
        manifest.name = app
        manifest.repository.url =
            "https ://github.com/mycozycloud/cozy-#{app}.git"
        manifest.user = app
        client.lightUpdate manifest, token, (err, res, body) ->
            if (res.statusCode isnt 200)
                console.log "Update failed"
                console.log err if err
                if res.body?
                    if res.body.msg? then console.log res.body.msg else console.log res.body
            else
                client.brunch manifest, ->
                    console.log "#{app} sucessfully updated"

program
    .command("uninstall-all <token>")
    .description("Uninstall all apps from haibu")
    .action (token) ->
        console.log "Uninstall all apps..."

        client.cleanAll token, (err, res) ->
            if err or res.statusCode isnt 200
                console.log "Uninstall all failed"
                console.log err if err
                if res.body?
                    if res.body.msg? then console.log res.body.msg else console.log res.body
            else
                console.log "All apps sucessfully uinstalled"

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

#program
    #.command("script_arg <app> <script> <argument>")
    #.description("(Broken) Launch script that comes with given application")
    #.action (app, script, argument) ->
        #console.log "Run script #{script} for #{app}..."
        #path = "./node_modules/haibu/local/cozy/#{app}/cozy-#{app}/"
        #child = exec "cd #{path}; coffee #{script}.coffee #{argument}", \
                     #(error, stdout, stderr) ->
            #console.log stdout
            #if error != null
                #console.log "exec error: #{error}"
                #console.log "stderr: #{stderr}"

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
                    if err
                        console.log "#{app}: " + "down".red
                    else
                        console.log "#{app}: " + "up".green
                    callback()

        async.series [
            checkApp("haibu", "http://localhost:9002/", "version")
            checkApp("data-system", "http://localhost:9101/")
            checkApp("indexer", "http://localhost:9102/")
            checkApp("home", "http://localhost:9103/")
            checkApp("proxy", "http://localhost:9104/", "routes")
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
    .command("reinstall-all <token>")
    .description("Reinstall all user applications")
    .action ->
        installApp = (app, token) ->
            (callback) ->
                console.log "Install started for #{app.name}..."
                manifest.name = app.name
                manifest.repository.url = app.git
                manifest.user = app.user

                client.clean manifest, token, (err, res, body) ->
                    client.start manifest, token, (err, res, body) ->
                        if err or res.statusCode isnt 200
                            console.log "Install failed"
                            console.log err if err
                            if res.body?
                                if res.body.msg? then console.log res.body.msg else console.log res.body
                        else
                            client.brunch manifest, token, ->
                                console.log "#{app.name} sucessfully installed"
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

# This program is suited only to manage your cozy installation from the inside
# Moreover app management works only for apps make by Cozy Cloud company.
# If you want a friendly application manager you should use the
# appmanager.coffee script.

program = require 'commander'
async = require "async"
fs = require "fs"
axon = require 'axon'
exec = require('child_process').exec
path = require('path')
log = require('printit')()
humanize = require('humanize')

request = require("request-json-light")

pkg = require '../package.json'
version = pkg.version

appsPath = '/usr/local/cozy/apps'

helpers = require './helpers'
application = require './application'
stackApplication = require './stack_application'
monitoring = require './monitoring'
db = require './database'

logError = helpers.logError
clients = helpers.clients

STACK = ['data-system', 'home', 'proxy']

program
    .version(version)
    .usage('<action> <app>')


## Applications management ##

# Install
#
program
    .command("install <name> ")
    .description("Install application")
    .option('-r, --repo <repo>', 'Use specific repo')
    .option('-b, --branch <branch>', 'Use specific branch')
    .option('-d, --displayName <displayName>', 'Display specific name')
    .option('-t , --timeout <timeout>', 'Configure timeout (in millisecond)' +
        ', -t false to remove timeout)')
    .action (name, options) ->
        if name.indexOf('https://') isnt -1
            return log.info 'Use option -r to specify application repository'
        log.info "Install started for #{name}..."
        if name is 'controller'
            err = new Error "Controller should be installed with command " +
                "'npm -g install cozy-controller'"
            logError err, 'Install failed for controller'
        if name in STACK
            installation = stackApplication.install
        else
            installation = application.install
        installation name, options, (err) ->
            if err?
                logError err, "Install failed for #{name}."
            else
                log.info "#{name} was successfully installed."


# Install cozy stack (home, ds, proxy)
program
    .command("install-cozy-stack")
    .description("Install cozy via the Cozy Controller")
    .action () ->
        async.eachSeries STACK, (app, cb) ->
            log.info "Install started for #{app}..."
            stackApplication.install app, {}, (err) ->
                if err?
                    logError err, "Install failed for #{app}."
                    cb(err)
                else
                    log.info '...ok'
                    cb()
        , (err) ->
            if err?
                logError err, "Install failed for cozy stack."
            else
                log.info 'Cozy stack successfully installed.'


# Uninstall
program
    .command("uninstall <app>")
    .description("Remove application")
    .action (app) ->
        log.info "Uninstall started for #{app}..."
        if app in STACK
            uninstallation = stackApplication.uninstall
        else
            uninstallation = application.uninstall
        uninstallation app, (err) ->
            if err?
                logError err, "Uninstall failed for #{app}."
            else
                log.info "#{app} successfully uninstalled."


# Start
program
    .command("start <app>")
    .description("Start application")
    .action (app) ->
        log.info "Starting #{app}..."
        if app in STACK
            start = stackApplication.start
        else
            start = application.start
        start app, (err) ->
            if err?
                logError err, "Start failed for #{app}."
            else
                log.info "#{app} successfully started."

# Restart
program
    .command("restart <app>")
    .description("Start application")
    .action (app) ->
        log.info "Restart #{app}..."
        if app in STACK
            start = stackApplication.start
        else
            start = application.start
        start app, (err) ->
            if err?
                logError err, "Restart failed for #{app}."
            else
                log.info "#{app} successfully restarted."

# Restart cozy stack
program
    .command("restart-cozy-stack")
    .description("Restart cozy through controller")
    .action () ->
        async.eachSeries STACK, (app, cb) ->
            log.info "Restart #{app}..."
            stackApplication.start app, (err) ->
                if err?
                    logError err, "Restart failed for #{app}."
                    cb(err)
                else
                    log.info '...ok'
                    cb()
        , (err) ->
            if err?
                logError err, "restart failed for cozy stack."
            else
                log.info 'Cozy stack successfully restarted.'

# Stop
program
    .command("stop <app>")
    .description("Stop application")
    .action (app) ->
        log.info "Stopping #{app}..."
        if app in STACK
            stop = stackApplication.stop
        else
            stop = application.stop
        stop app, (err) ->
            if err?
                logError err, "Stop failed for #{app}."
            else
                log.info "#{app} successfully stoped."

# Stop all user applications
program
    .command("stop-all")
    .description("Stop all user applications")
    .action ->
        application.getApps (err, apps) ->
            if err?
                logError err, "Retrieve applications failed."
            else
                async.eachSeries apps, (app, cb) ->
                    log.info "Stopping #{app.slug} ..."
                    application.stop app.slug, (err) ->
                        if err?
                            logError err, "Stop failed for #{app.slug}."
                            cb err
                        else
                            log.info "...ok"
                            cb()
                , (err) ->
                    if err?
                        logError err, "Stop failed."
                    else
                        log.info "All applications successfully stopped."


# Update
program
    .command("update <app>")
    .description(
        "Update application (git + npm) and restart it.")
    .action (app) ->
        log.info "Updating #{app}..."
        if app is 'controller'
            err = new Error "Controller should be updated with command " +
                "'npm -g update cozy-controller'"
            logError err, 'Update failed for controller'
        if app in STACK
            update = stackApplication.update
        else
            update = application.update
        update app, (err) ->
            if err?
                logError err, "Update failed for #{app}."
            else
                log.info "#{app} successfully updated."

# Update cozy stack
program
    .command("update-cozy-stack")
    .description(
        "Update cozy stack (home/proxy/data-system)")
    .action () ->
        async.eachSeries ['data-system', 'home', 'proxy'], (app, cb) ->
            log.info "Update #{app}..."
            stackApplication.update app, (err) ->
                if err?
                    logError err, "Update failed for #{app}."
                    cb(err)
                else
                    log.info '...ok'
                    cb()
        , (err) ->
            if err?
                logError err, "Update failed for cozy stack."
            else
                log.info 'Cozy stack successfully updated.'

# Update all user application
program
    .command("update-all")
    .description("Update all user applications")
    .action ->
        application.getApps (err, apps) ->
            if err?
                logError err, "Retrieve applications failed."
            else
                async.mapSeries apps, (app, cb) ->
                    log.info "Update #{app.name} ..."
                    application.update app.name, (err) ->
                        if err?
                            log.error err
                            log.error "Update failed for #{app.slug}."
                            cb null, app.name
                        else
                            log.info "...ok"
                            cb null, null
                , (err, res) ->
                    res = res.filter (name) -> return name?
                    if res.length > 0
                        logError err, "Update failed for #{res.join ', '}"
                    else
                        log.info "All applications successfully updated."

program
    .command("update-all-cozy-stack")
    .description(
        "Update all cozy stack application (DS + proxy + home + controller)")
    .action () ->
        log.info "Update all cozy stack ..."
        stackApplication.updateAll (err) ->
            if err?
                logError err, "Update all cozy stack failed."
            else
                log.info "All cozy stack successfully updated."

# Change application branch
program
    .command("change-branch <app> <branch>")
    .description("Change application branch")
    .action (app, branch) ->
        log.info "Change #{app} for branch #{branch}..."
        if app in ['data-system', 'home', 'proxy']
            changeBranch = stackApplication.changeBranch
        else
            changeBranch = application.changeBranch
        changeBranch app, branch, (err) ->
            if err?
                logError err, "Start failed for #{app}."
            else
                log.info "#{app} successfully started."


# Init database
# Usefull to generate new Cozy with an empty database
# Add all user application installed on disk in database
program
    .command("init-db [path]")
    .description("Install application")
    .action (path) ->
        # Check if database is empty
        clientCouch = helpers.clients.couch
        clientCouch.get "#{helpers.dbName}/_design/application/_view/all", {}, (err, res, body) ->
            if not err? and body.total_rows isnt 0
                log.error "Your database isn't empty"
                #return

            path = path or '/usr/local/cozy/apps'
            apps = fs.readdirSync path
            async.eachSeries apps, (app, cb) ->
                if app is 'stack.json'
                    cb()
                else if app in STACK
                    cb()
                else
                    application.installFromDisk app, cb
            , (err) ->
                if err?
                    log.error err
                    log.error 'Error in database initialization'
                else
                    log.info 'Database successfully initialized'




# Reinstall all user applications (usefull for cozy relocation)
program
    .command('reinstall-missing-app')
    .description('Reinstall all user applications, usefull for cozy relocation')
    .action () ->
        application.getApps (err, apps) ->
            if err?
                logError err, "Retrieve applications failed."
            else
                async.forEachSeries apps, (app, callback) ->
                    switch app.state
                        when 'installed'
                            # if application is marked 'installed' :
                            #     reinstall it with controller
                            log.info "#{app.slug} : installed. Reinstall " +
                                "application if necessary..."
                            application.installController app, callback
                        when 'stopped'
                            # if application is marked 'stopped' :
                            #     reinstall and then stop it with controller
                            log.info "#{app.slug} : stopped. Reinstall " +
                                "application if necessary and stop it..."
                            application.installController app, (err) ->
                                return callback err if err?
                                application.stopController app.slug, callback
                        when 'installing'
                            # if application is marked 'installing' :
                            #     reinstall with home
                            log.info "#{app.slug} : installing. " +
                                "Reinstall application..."
                            application.reinstall app.slug, app, callback
                        when 'broken'
                            # if application is marked 'broken' :
                            #     reinstall with home
                            log.info "#{app.slug} : broken. Try to reinstall " +
                                "application..."
                            application.reinstall app.slug, app, callback
                        else
                            callback()
                , (err) ->
                    if err?
                        logError err, "Reinstall missing app failed."
                    else
                        log.info "All missing applications successfully " +
                            "reinstall."



## Start applicationn without controller in a production environment.
# * Add/Replace application in database (for home and proxy)
# * Reset proxy
# * Start application with environment variable
# * When application is stopped : remove application in database and reset proxy
program
    .command("start-standalone <port>")
    .description("Start application without controller")
    .action (port) ->
        application.startStandalone port, (err) ->
            if err?
                logError err, "Start standalone failed."


## Stop applicationn without controller in a production environment.
# * Remove application in database and reset proxy
# * Usefull if start-standalone doesn't remove app
program
    .command("stop-standalone")
    .description("Stop application without controller")
    .action () ->
        application.stopStandalone (err) ->
            if err?
                logError err, "Stop standalone failed."

# Versions

cozyStack = ['controller', 'data-system', 'home', 'proxy']

program
    .command("versions-stack")
    .description("Display stack applications versions")
    .action () ->
        log.raw ''
        log.raw 'Cozy Stack:'.bold
        async.forEachSeries cozyStack, (app, cb) ->
            stackApplication.getVersion app, (version) ->
                log.raw "#{app}: #{version}"
                cb()
        , (err) ->
            log.raw "monitor: #{version}"


program
    .command("versions")
    .description("Display applications versions")
    .option('--json', 'Display result in JSON')
    .action (options) ->
        if options.json?
            res = {}
        else
            log.raw ''
            log.raw 'Cozy Stack:'.bold
        stackApplication.getVersions (err, versions) ->
            if err?
                log.error "Error when retrieving stack applications."
            else
                versions.forEach (app) ->
                    if app.needsUpdate
                        avail = " (update available: #{app.lastVersion})"
                    else
                        avail = ""
                    if options.json?
                        res[app.name] = app.version
                    else
                        log.raw "#{app.name}: #{app.version} #{avail}"
            if options.json?
                res.monitor = version
            else
                log.raw "monitor: #{version}"
                log.raw ''
                log.raw "Other applications: ".bold
            application.getApps (err, apps) ->
                if err?
                    log.error "Error when retrieving user application."
                else
                    async.forEachSeries apps, (app, cb)->
                        application.getVersion app, (version)->
                            if app.needsUpdate
                                avail = " (update available: #{app.lastVersion})"
                            else
                                avail = ""
                            if options.json?
                                res[app.name] = version
                            else
                                log.raw "#{app.name}: #{version} #{avail}"
                            cb()
                    , (err) ->
                        if options.json
                            log.raw JSON.stringify(res, null, 2)


## Monitoring ##
program
    .command("dev-route:start <slug> <port>")
    .description("Create a route so we can access it by the proxy. ")
    .action (slug, port) ->
        monitoring.startDevRoute slug, port, (err) ->
            if err?
                logError err, 'Start route failed'
            else
                log.info "Route was successfully created."

program
    .command("dev-route:stop <slug>")
    .action (slug) ->
        monitoring.stopDevRoute slug, (err) ->
            if err?
                logError err, 'Stop route failed'
            else
                log.info "Route was successfully removed."

program
    .command("routes")
    .description("Display routes currently configured inside proxy.")
    .action ->
        log.info "Display proxy routes..."
        monitoring.getRoutes (err) ->
            if err?
                logError err, 'Display routes failed'


program
    .command("module-status <module>")
    .description("Give status of given in an easy to parse way.")
    .option('--json', 'Display result in JSON')
    .action (module, options) ->
        monitoring.moduleStatus module, (status) ->
            if options.json
                res = {}
                res[module] = status
                console.log(JSON.stringify(res, null, 2))
            else
                log.info status

program
    .command("status")
    .description("Give current state of cozy platform applications")
    .option('--json', 'Display result in JSON')
    .option('-r, --raw', "Don't display color")
    .action (options) ->
        opt =
            raw: options.raw
            json: options.json
        monitoring.status opt, (err, res) ->
            if err?
                logError err, "Cannot display status"
            else
                if options.json
                    log.raw JSON.stringify(res, null, 2)


program
    .command("log <app> <type>")
    .description("Display application log with cat or tail -f")
    .action (app, type, environment) ->
        monitoring.log app, type, (err) ->
            if err?
                logError err, "Cannot display log"


## Database ##

program
    .command("curlcouch <url> [method]")
    .description("""Send request curl -X <method>
        http://id:pwd@couchhost:couchport/cozy/<url> to couchdb """)
    .option('--pretty', "Pretty print result")
    .action (url, method, options) ->
        if not method
            method = 'GET'
        [user, pwd] = helpers.getAuthCouchdb false
        request = "curl -X #{method} "
        if user is '' and pwd is ''
            request += "http://localhost:5984/cozy/#{url}"
        else
            request += "http://#{user}:#{pwd}@localhost:5984/cozy/#{url}"
        requestOptions =
            maxBuffer: 10*1024*1024
        child = exec request, requestOptions, (err, stdout, stderr) ->
            if options.pretty?
                try
                    console.log JSON.stringify(JSON.parse(stdout), null, 2)
                catch e
                    console.log stdout
            else
                console.log stdout

program
    .command("compact [database]")
    .description("Start couchdb compaction")
    .action (database) ->
        database ?= "cozy"
        log.info "Start couchdb compaction on #{database} ..."
        db.compact database, (err)->
            if err?
                logError err, "Cannot compact database"
            else
                log.info "#{database} compaction succeeded"
                process.exit 0


program
    .command("compact-views <view> [database]")
    .description("Start couchdb compaction of the given view")
    .action (view, database) ->
        database ?= "cozy"
        log.info "Start views compaction on #{database} for #{view} ..."
        db.compactViews view, database, (err)->
            if err?
                logError err, "Cannot compact view"
            else
                log.info "#{view} compaction succeeded"
                process.exit 0



program
    .command("compact-all-views [database]")
    .description("Start couchdb compaction of all views")
    .action (database) ->
        database ?= "cozy"
        database ?= "cozy"
        log.info "Start views compaction on #{database}..."
        db.compactAllViews database, (err)->
            if err?
                logError err, "Cannot compact views"
            else
                log.info "Views compaction succeeded"
                process.exit 0


# List infos on all views
program
    .command("views-list [database]")
    .description("List infos on all views")
    .option('--json', 'Display result in JSON')
    .action (database, options) ->
        database ?= "cozy"
        db.listAllViews database, (err, infos)->
            if err?
                logError err, "Cannot list views"
            else
                # sort by view size
                infos.sort (a, b) ->
                    if a.size < b.size
                        return -1
                    else
                        return 1
                if options.json
                    res = {}
                    infos.map (info) ->
                        res[info.name] = info
                        res[info.name].human = humanize.filesize info.size
                    console.log(JSON.stringify(res, null, 2))
                else
                    infos.map (info) ->
                        name = "#{info.name}                    "
                        size = "          #{humanize.filesize info.size}"
                        console.log """
                          #{name.substr(0, 20)} #{info.hash} #{size.substr -15}
                        """
                process.exit 0


program
    .command("cleanup [database]")
    .description("Start couchdb cleanup")
    .action (database) ->
        database ?= "cozy"
        log.info "Start couchdb cleanup on #{database}..."
        db.cleanup database, (err) ->
            if err?
                logError err, "Cannot cleanup database"
            else
                log.info "Cleanup succeeded"
                process.exit 0

## Backup ##

program
    .command("backup <target>")
    .description("Start couchdb replication to the target")
    .action (target) ->
        log.info "Backup database ..."
        data =
            source: "cozy"
            target: target
        db.backup data, (err) ->
            if err?
                logError err, "Cannot backup database"
            else
                log.info "Backup succeeded"
                process.exit 0


program
    .command("reverse-backup <backup> <username> <password>")
    .description("Start couchdb replication from target to cozy.
        <backup> should be 'https://<ip>:<port>/<database>' ")
    .action (backup, usernameBackup, passwordBackup) ->
        log.info "Reverse backup..."
        db.reverseBackup backup, usernameBackup, passwordBackup, (err) ->
            if err?
                logError err, "Cannot reverse backup"
            else
                log.info "Reverse backup succeeded"
                process.exit 0


## Others ##

program
    .command("reset-proxy")
    .description("Reset proxy routes list of applications given by home.")
    .action ->
        log.info "Reset proxy routes"

        clients.proxy.get "routes/reset", (err, res, body) ->
            if err
                logError helpers.makeError err, body, "Reset routes failed"
            else
                log.info "Reset proxy succeeded."


program
    .command("*")
    .description("Display the help message for an unknown command.")
    .action ->
        log.error 'Unknown command, showing help instead.'
        program.outputHelp()

program.parse process.argv

unless process.argv.slice(2).length
    program.outputHelp()

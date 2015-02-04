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
path = require('path')
log = require('printit')()

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
        log.info "Install started for #{app}..."
        if app in ['data-system', 'home', 'proxy']
            installation = stackApplication.install
        else
            installation = application.install
        installation app, options, (err) ->
            if err?
                logError err, "Install failed for #{app}."
            else
                log.info "#{app} was successfully installed."


# Install cozy stack (home, ds, proxy)
program
    .command("install-cozy-stack")
    .description("Install cozy via the Cozy Controller")
    .action () ->
        async.eachSeries ['data-system', 'home', 'proxy'], (app, cb) ->
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
        if app in ['data-system', 'home', 'proxy']
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
        if app in ['data-system', 'home', 'proxy']
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
        if app in ['data-system', 'home', 'proxy']
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
    .description("Restart cozy trough controller")
    .action () ->
        async.eachSeries ['data-system', 'home', 'proxy'], (app, cb) ->
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
        if app in ['data-system', 'home', 'proxy']
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
    .command("update <app> [repo]")
    .description(
        "Update application (git + npm) and restart it. Option repo " +
        "is usefull only if app comes from a specific repo")
    .action (app, repo) ->
        log.info "Updating #{app}..."
        if app in ['data-system', 'home', 'proxy']
            update = stackApplication.update
        else
            update = application.update
        update app, repo, (err) ->
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
            stackApplication.update app, {}, (err) ->
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
                async.eachSeries apps, (app, cb) ->
                    log.info "Update #{app.slug} ..."
                    application.update app.slug, {}, (err) ->
                        if err?
                            logError err, "Update failed for #{app.slug}."
                            cb err
                        else
                            log.info "...ok"
                            cb()
                , (err) ->
                    if err?
                        logError err, "Update failed."
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
                logError err, "All cozy stack successfully updated."

# Force restart all user application
program
    .command("force-restart")
    .description("Force application restart - usefull for relocation")
    .action () ->
        application.getApps (err, apps) ->
            if err?
                logError err, "Retrieve applications failed."
            else
                async.forEachSeries apps, (app, callback) ->
                    switch app.state
                        when 'installed'
                            log.info "Restart #{app.slug}..."
                            application.restart app.slug, callback
                        when 'stopped'
                            log.info "Restop #{app.slug}..."
                            application.restop app.slug, callback
                        when 'installing'
                            log.info "Reinstall #{app.slug}..."
                            app.repo = app.git
                            application.reinstall app.slug, app, callback
                        when 'broken'
                            log.info "Reinstall #{app.slug}..."
                            application.reinstall app.slug, app, callback
                        else
                            callback()
                , (err) ->
                    if err?
                        logError err, "Force restart failed."
                    else
                        log.info "All applications successfully restart."



program
    .command('autostop-all')
    .description("Put all applications in autostop mode" +
        "(except pfm, emails, feeds, nirc and konnectors)")
    .action ->
        application.getApps (err, apps) ->
            if err?
                logError err, "Retrieve applications failed."
            else
                async.forEachSeries apps, (app, cb) ->
                    log.info "Autostop #{app.slug} ..."
                    application.autoStop app, (err) ->
                        if err?
                            logError err, "Autostop failed for #{app.slug}."
                            cb err
                        else
                            log.info "...ok"
                            cb()
                , (err) ->
                    if err?
                        logError err, "Autostop failed."
                    else
                        log.info "All applications successfully autostoppable."


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

program
    .command("versions-stack")
    .description("Display stack applications versions")
    .action () ->
        log.raw ''
        log.raw 'Cozy Stack:'.bold
        async.forEachSeries ['controller', 'data-system', 'home', 'proxy', 'indexer'], (app, cb) ->
            stackApplication.getVersion app, (version) ->
                log.raw "#{app}: #{version}"
                cb()
        , (err) ->
            log.raw "monitor: #{version}"


program
    .command("versions")
    .description("Display applications versions")
    .action () ->
        log.raw ''
        log.raw 'Cozy Stack:'.bold
        async.forEachSeries ['controller', 'data-system', 'home', 'proxy', 'indexer'], (app, cb) ->
            stackApplication.getVersion app, (version) ->
                log.raw "#{app}: #{version}"
                cb()
        , (err) ->
            log.raw "monitor: #{version}"
            log.raw ''
            log.raw "Other applications: ".bold
            application.getApps (err, apps) ->
                if err?
                    log.error "Error when retrieve user application."
                else
                async.forEachSeries apps, (app, cb)->
                    application.getVersion app, (version)->
                        log.raw "#{app.name}: #{version}"
                        cb()


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
    .action (module) ->
        monitoring.moduleStatus module, (status) ->
            log.info status

program
    .command("status")
    .description("Give current state of cozy platform applications")
    .action ->
        monitoring.status (err) ->
            if err?
                logError err, "Cannot display status"


program
    .command("log <app> <type>")
    .description("Display application log with cat or tail -f")
    .action (app, type, environment) ->
        monitoring.log app, type, (err) ->
            if err?
                logError err, "Cannot display log"


## Database ##

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
    .description("Start couchdb compaction")
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
    .description("Start couchdb compaction")
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
        log.info "Backup database in #{target}"
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
    .description("Start couchdb replication from target to cozy")
    .action (backup, usernameBackup, passwordBackup) ->
        log.info "Reverse backup..."
        db.reverseBackup backup, unsernameBackup, passwordBackup, (err) ->
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
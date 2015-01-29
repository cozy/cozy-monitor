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
database = require './database'


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


# Install cozy stack (home, ds, proxy)
program
    .command("install-cozy-stack")
    .description("Install cozy via the Cozy Controller")
    .action () ->
        installStackApp 'data-system', () ->
            installStackApp 'home', () ->
                installStackApp 'proxy', () ->
                    log.info 'Cozy stack successfully installed.'


# Uninstall
program
    .command("uninstall <app>")
    .description("Remove application")
    .action (app) ->
        log.info "Uninstall started for #{app}..."
        if app in ['data-system', 'home', 'proxy']
            
        else
            


# Start
program
    .command("start <app>")
    .description("Start application")
    .action (app) ->
        log.info "Starting #{app}..."
        if app in ['data-system', 'home', 'proxy']
            
        else
            


program
    .command("force-restart")
    .description("Force application restart - usefull for relocation")
    .action () ->
       


## Start applicationn without controller in a production environment.
# * Add/Replace application in database (for home and proxy)
# * Reset proxy
# * Start application with environment variable
# * When application is stopped : remove application in database and reset proxy
program
    .command("start-standalone <port>")
    .description("Start application without controller")
    .action (port) ->
        


## Stop applicationn without controller in a production environment.
# * Remove application in database and reset proxy
# * Usefull if start-standalone doesn't remove app
program
    .command("stop-standalone")
    .description("Start application without controller")
    .action () ->

# Stop

program
    .command("stop <app>")
    .description("Stop application")
    .action (app) ->
        log.info "Stopping #{app}..."
        if app in ['data-system', 'home', 'proxy']

        else


program
    .command("stop-all")
    .description("Stop all user applications")
    .action ->


program
    .command('autostop-all')
    .description("Put all applications in autostop mode" +
        "(except pfm, emails, feeds, nirc and konnectors)")
    .action ->

# Restart

program
    .command("restart <app>")
    .description("Restart application")
    .action (app) ->
        log.info "Stopping #{app}..."
        if app in ['data-system', 'home', 'proxy']

        else


program
    .command("restart-cozy-stack")
    .description("Restart cozy trough controller")
    .action () ->
        restartApp 'data-system', () =>
            restartApp 'home', () =>
                restartApp 'proxy', () =>
                    log.info 'Cozy stack successfully restarted.'


# Update

program
    .command("update <app> [repo]")
    .description(
        "Update application (git + npm) and restart it. Option repo " +
        "is usefull only if app comes from a specific repo")
    .action (app, repo) ->
        log.info "Updating #{app}..."
        if app in ['data-system', 'home', 'proxy']

        else


program
    .command("update-cozy-stack")
    .description(
        "Update application (git + npm) and restart it through controller")
    .action () ->
        updateApp 'data-system', () =>
            updateApp 'home', () =>
                updateApp 'proxy', () =>
                    log.info 'Cozy stack successfully updated'

program
    .command("update-all-cozy-stack [token]")
    .description(
        "Update all cozy stack application (DS + proxy + home + controller)")
    .action (token) ->
        if token
            client = new ControllerClient
                token: token
        updateController ->
            updateApp 'data-system', ->
                updateApp 'home', ->
                    updateApp 'proxy', ->
                        restartController ->
                            log.info 'Cozy stack successfully updated'


program
    .command("update-all")
    .description("Reinstall all user applications")
    .action ->
        homeClient.host = homeUrl
        homeClient.get "api/applications/", (err, res, apps) ->
            funcs = []
            if apps? and apps.rows?
                for app in apps.rows
                    func = updateApp app
                    funcs.push func

                async.series funcs, ->
                    log.info "\nAll apps reinstalled."
                    log.info "Reset proxy routes"

                    statusClient.host = proxyUrl
                    statusClient.get "routes/reset", (err, res, body) ->
                        if err
                            handleError err, body, "Cannot reset proxy routes."
                        else
                            log.info "Resetting proxy routes succeeded."


# Versions


program
    .command("versions-stack")
    .description("Display stack applications versions")
    .action () ->
        log.raw ''
        log.raw 'Cozy Stack:'.bold
        getVersion "controller"
        getVersion "data-system"
        getVersion "home"
        getVersion 'proxy'
        getVersionIndexer (indexerVersion) =>
            log.raw "indexer: #{indexerVersion}"
            log.raw "monitor: #{version}"


program
    .command("versions")
    .description("Display applications versions")
    .action () ->
        log.raw ''
        log.raw 'Cozy Stack:'.bold
        getVersion "controller"
        getVersion "data-system"
        getVersion "home"
        getVersion 'proxy'
        getVersionIndexer (indexerVersion) =>
            log.raw "indexer: #{indexerVersion}"
            log.raw "monitor: #{version}"
            log.raw ''
            log.raw "Other applications: ".bold
            homeClient.host = homeUrl
            homeClient.get "api/applications/", (err, res, apps) ->
                if apps?.rows?
                    log.raw "#{app.name}: #{app.version}" for app in apps.rows


## Monitoring ###


program
    .command("dev-route:start <slug> <port>")
    .description("Create a route so we can access it by the proxy. ")
    .action (slug, port) ->

program
    .command("dev-route:stop <slug>")
    .action (slug) ->

program
    .command("routes")
    .description("Display routes currently configured inside proxy.")
    .action ->
        log.info "Display proxy routes..."


program
    .command("module-status <module>")
    .description("Give status of given in an easy to parse way.")
    .action (module) ->

program
    .command("status")
    .description("Give current state of cozy platform applications")
    .action ->
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


## Database ##

program
    .command("compact [database]")
    .description("Start couchdb compaction")
    .action (database) ->
        database ?= "cozy"
       


program
    .command("compact-views <view> [database]")
    .description("Start couchdb compaction")
    .action (view, database) ->
        database ?= "cozy"



program
    .command("compact-all-views [database]")
    .description("Start couchdb compaction")
    .action (database) ->
        database ?= "cozy"

program
    .command("cleanup [database]")
    .description("Start couchdb cleanup")
    .action (database) ->
        database ?= "cozy"

## Backup ##

program
    .command("backup <target>")
    .description("Start couchdb replication to the target")
    .action (target) ->
        data =
            source: "cozy"
            target: target



program
    .command("reverse-backup <backup> <username> <password>")
    .description("Start couchdb replication from target to cozy")
    .action (backup, usernameBackup, passwordBackup) ->
        log.info "Reverse backup..."


        [username, password] = getAuthCouchdb()


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


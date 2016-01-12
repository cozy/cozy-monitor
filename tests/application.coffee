stackApplication = require '../lib/stack_application'
application = require '../lib/application'
should = require('chai').should()
fs = require 'fs'

SECOND = 1000
MINUTE = 60 * SECOND

describe "Application management", ->
    before (done) ->
        @timeout 2 * MINUTE
        stackApplication.install 'data-system', {}, (err) ->
            should.not.exist err
            stackApplication.install 'home', {}, (err) ->
                should.not.exist err
                stackApplication.install 'proxy', {}, (err) ->
                    should.not.exist err
                    done()

    after (done) ->
        @timeout 2 * MINUTE
        application.uninstall 'calendar', (err) ->
            stackApplication.uninstall 'data-system', (err) ->
                stackApplication.uninstall 'home', (err) ->
                    stackApplication.uninstall 'proxy', (err) ->
                        done()

    describe "Install", ->

        describe "Photos installation ", ->
            it "When I send a request to install photos", (done) ->
                @timeout 3 * MINUTE
                application.install 'photos', {}, (err) =>
                    @err = err
                    done()

            it "Then error should not exist", ->
                should.not.exist @err

            it "And photos should be install", (done) ->
                fs.exists '/usr/local/cozy/apps/photos', (exist) ->
                    exist.should.equal true
                    done()

            it "And photos should be started", (done) ->
                application.check(raw: true, 'photos', 'http://localhost:9119') (err, state) ->
                    console.log(err, state)
                    state[1].should.equal 'up'
                    done()

        describe "Install with options", ->

            it "When I send a request to install photos with options", (done) ->
                @timeout 3 * MINUTE
                options =
                    "repo": 'https://github.com/poupotte/cozy-calendar.git'
                    "branch": 'standalone'
                    "displayName": 'test'
                application.install 'calendar', options, (err) =>
                    @err = err
                    done()

            it "Then error should not exist", ->
                should.not.exist @err

            it "And calendar should be install", (done) ->
                fs.exists '/usr/local/cozy/apps/calendar', (exist) ->
                    exist.should.equal true
                    done()

            it "And calendar should be started", (done) ->
                application.check(raw: true, 'calendar', 'http://localhost:9113') (err, state) ->
                    state[1].should.equal 'up'
                    done()

            it "And displayName should be 'test'", (done) ->
                application.getApps (err, apps) =>
                    for app in apps
                        if app.slug is "calendar"
                            @app = app
                            app.displayName.should.equal 'test'
                            done()

            it "And repository should be 'https://github.com/poupotte/cozy-calendar.git'", ->
                @app.git.should.equal 'https://github.com/poupotte/cozy-calendar.git'

            it "And branch should be 'standalone'", ->
                @app.branch.should.equal 'standalone'

        describe "Try to install an application already installed", ->
            it "When I send a request to install photos", (done) ->
                @timeout 3 * MINUTE
                application.install 'photos', {}, (err) =>
                    @err = err
                    done()

            it "Then error should exist", ->
                should.exist @err

            it "And error should explain app already exist", ->
                @err.msg
                @err.toString().indexOf('already similarly named app').should.not.equal -1


        describe "Try to install an undefined application", ->
            it "When I send a request to install", (done) ->
                @timeout 3 * MINUTE
                application.install 'test', {}, (err) =>
                    @err = err
                    done()

            it "Then error should exist", ->
                should.exist @err

            it "And error should explain repo doesn't exist", ->
                @err.msg
                @err.toString().indexOf("Default git repo https://github.com/cozy/cozy-test.git doesn't exist").should.not.equal -1

    describe "Restart", ->

        describe "Restart photos", ->
            it "When I send a request to restart photos", (done) ->
                @timeout 2 * MINUTE
                application.restart 'photos', (err) =>
                    @err = err
                    done()

            it "Then error should not exist", ->
                should.not.exist @err

            it "And photos should be started", (done) ->
                application.check(raw: true, 'photos', 'http://localhost:9119') (err, state) ->
                    state[1].should.equal 'up'
                    done()

        describe "Try to restart a application which isn't installed", ->
            it "When I send a request to restart", (done) ->
                @timeout 2 * MINUTE
                application.restart 'test', (err) =>
                    @err = err
                    done()

            it "Then error should exist", ->
                should.exist @err

            it "And error should be 'not found'", ->
                @err.msg
                @err.toString().indexOf('application test not found').should.not.equal -1

    describe "Stop", ->

        describe "Stop photos", ->
            it "When I send a request to stop photos", (done) ->
                @timeout 2 * MINUTE
                application.stop 'photos', (err) =>
                    @err = err
                    done()

            it "Then error should not exist", ->
                should.not.exist @err

            it "And photos should be stopped", (done) ->
                application.check(raw: true, 'photos', 'http://localhost:9119') (err, state) ->
                    state[1].should.equal 'down'
                    done()

        describe "Try to stop application undefined", ->
            it "When I send a request to stop test", (done) ->
                @timeout 2 * MINUTE
                application.stop 'test', (err) =>
                    @err = err
                    done()

            it "Then error should exist", ->
                should.exist @err

            it "And error should be 'not found'", ->
                @err.msg
                @err.toString().indexOf('application test not found').should.not.equal -1


    describe "Restop", ->

        describe "Restop photos", ->
            it "When I send a request to restop photos", (done) ->
                @timeout 2 * MINUTE
                application.restop 'photos', (err) =>
                    @err = err
                    done()

            it "Then error should not exist", ->
                should.not.exist @err

            it "And photos should be stopped", (done) ->
                application.check(raw: true, 'photos', 'http://localhost:9119') (err, state) ->
                    state[1].should.equal 'down'
                    done()

        describe "Restop application undefined", ->
            it "When I send a request to restop", (done) ->
                @timeout 2 * MINUTE
                application.restop 'test', (err) =>
                    @err = err
                    done()

            it "Then error should exist", ->
                should.exist @err

            it "And error should be 'not found'", ->
                @err.msg
                @err.toString().indexOf('application test not found').should.not.equal -1


    describe "Start", ->

        describe "Start photos", ->
            it "When I send a request to start photos", (done) ->
                @timeout 2 * MINUTE
                application.start 'photos', (err) =>
                    @err = err
                    done()

            it "Then error should not exist", ->
                should.not.exist @err

            it "And photos should be started", (done) ->
                application.check(raw: true, 'photos', 'http://localhost:9119') (err, state) ->
                    state[1].should.equal 'up'
                    done()

        describe "Try to start an application undefined", ->
            it "When I send a request to start", (done) ->
                @timeout 2 * MINUTE
                application.start 'test', (err) =>
                    @err = err
                    done()

            it "Then error should exist", ->
                should.exist @err

            it "And error should be 'not found'", ->
                @err.msg
                @err.toString().indexOf('application test not found').should.not.equal -1

    describe "Update", ->

        describe "Update photos", ->
            it "When I send a request to update photos", (done) ->
                @timeout 2 * MINUTE
                application.update 'photos', (err) =>
                    @err = err
                    done()

            it "Then error should not exist", ->
                should.not.exist @err

            it "And photos should be started", (done) ->
                application.check(raw: true, 'photos', 'http://localhost:9119') (err, state) ->
                    state[1].should.equal 'up'
                    done()

        describe "Update an application undefined", ->
            it "When I send a request to update", (done) ->
                @timeout 2 * MINUTE
                application.update 'test', (err) =>
                    @err = err
                    done()

            it "Then error should exist", ->
                should.exist @err

            it "And error should be 'not found'", ->
                @err.msg
                @err.toString().indexOf('application test not found').should.not.equal -1

    describe "Reinstall", ->

        describe "Reinstall photos", ->
            it "When I send a request to reinstall photos", (done) ->
                @timeout 2 * MINUTE
                application.start 'photos', (err) =>
                    @err = err
                    done()

            it "Then error should not exist", ->
                should.not.exist @err


            it "And data-system should be install", (done) ->
                fs.exists '/usr/local/cozy/apps/photos', (exist) ->
                    exist.should.equal true
                    done()

            it "And photos should be started", (done) ->
                application.check(raw: true, 'photos', 'http://localhost:9119') (err, state) ->
                    state[1].should.equal 'up'
                    done()

        describe "Try to reinstall an application undefined", ->
            it "When I send a request to reinstall", (done) ->
                @timeout 2 * MINUTE
                application.start 'test', (err) =>
                    @err = err
                    done()

            it "Then error should exist", ->
                should.exist @err

            it "And error should be 'not found'", ->
                @err.msg
                @err.toString().indexOf('application test not found').should.not.equal -1

    describe "Version", ->
        it "When I send a request to check photos", (done) ->
            @timeout 2 * MINUTE
            application.getApps (err, apps) =>
                if err?
                    console.log "Error when retrieve user application."
                else
                for app in apps
                    if app.name is "photos"
                        application.getVersion app, (version) =>
                            @version = version
                            done()

        it "Then version should exist", ->
            should.exist @version

        it "And version should equal to photos version", ->
            manifest = require '/usr/local/cozy/apps/photos/package.json'
            manifest.version.should.equal @version

    describe "Uninstall", ->

        describe "Uninstall photos", ->
            it "When I send a request to update photos", (done) ->
                @timeout 2 * MINUTE
                application.uninstall 'photos', (err) =>
                    @err = err
                    done()

            it "Then error should not exist", ->
                should.not.exist @err

            it "And photos should be stopped", (done) ->
                application.check(raw: true, 'photos', 'http://localhost:9119') (err, state) ->
                    state[1].should.equal 'down'
                    done()

            it "And photos should be uninstall", (done) ->
                fs.exists '/usr/local/cozy/apps/photos', (exist) ->
                    exist.should.equal false
                    done()

        describe "Try to uninstall an application undefined", ->
            it "When I send a request to update", (done) ->
                @timeout 2 * MINUTE
                application.uninstall 'test', (err) =>
                    @err = err
                    done()

            it "Then error should exist", ->
                should.exist @err

            it "And error should be 'not found'", ->
                @err.msg
                @err.toString().indexOf('Application not found').should.not.equal -1

stackApplication = require '../lib/stack_application'
monitoring = require '../lib/monitoring'
should = require('chai').should()
fs = require 'fs'

SECOND = 1000
MINUTE = 60 * SECOND

describe "Stack application management", ->

    describe "Install", ->
        it "When I send a request to install data-system", (done) ->
            @timeout 3 * MINUTE
            stackApplication.install 'data-system', {}, (err) =>
                @err = err
                done()

        it "Then error should not exist", ->
            should.not.exist @err

        it "And data-system should be install", (done) ->
            fs.exists '/usr/local/cozy/apps/data-system', (exist) ->
                exist.should.equal true
                done()

        it "And data-system should be started", (done) ->
            monitoring.moduleStatus 'data-system', (state) ->
                state.should.equal 'up'
                done()

    describe "Stop", ->
        it "When I send a request to stop data-system", (done) ->
            @timeout 3 * MINUTE
            stackApplication.stop 'data-system', (err) =>
                @err = err
                done()

        it "Then error should not exist", ->
            should.not.exist @err

        it "And data-system should be stopped", (done) ->
            monitoring.moduleStatus 'data-system', (state) ->
                state.should.equal 'down'
                done()

    describe "Start", ->
        it "When I send a request to start data-system", (done) ->
            @timeout 2 * MINUTE
            stackApplication.start 'data-system', (err) =>
                @err = err
                done()

        it "Then error should not exist", ->
            should.not.exist @err

        it "And data-system should be started", (done) ->
            monitoring.moduleStatus 'data-system', (state) ->
                state.should.equal 'up'
                done()

    describe "Update", ->
        it "When I send a request to update data-system", (done) ->
            @timeout 2 * MINUTE
            stackApplication.update 'data-system', (err) =>
                @err = err
                done()

        it "Then error should not exist", ->
            should.not.exist @err

        it "And data-system should be started", (done) ->
            monitoring.moduleStatus 'data-system', (state) ->
                state.should.equal 'up'
                done()

    describe "Version", ->
        it "When I send a request to check data-system", (done) ->
            @timeout 2 * MINUTE
            stackApplication.getVersion 'data-system', (version) =>
                @version = version
                done()

        it "Then version should exist", ->
            should.exist @version

        it "And version should equal to data-system version", ->
            manifest = require '/usr/local/cozy/apps/data-system/package.json'
            manifest.version.should.equal @version

    describe "Uninstall", ->
        it "When I send a request to update data-system", (done) ->
            @timeout 2 * MINUTE
            stackApplication.uninstall 'data-system', (err) =>
                @err = err
                done()

        it "Then error should not exist", ->
            should.not.exist @err

        it "And data-system should be stopped", (done) ->
            monitoring.moduleStatus 'data-system', (state) ->
                state.should.equal 'down'
                done()

        it "And data-system should be uninstall", (done) ->
            fs.exists '/usr/local/cozy/apps/data-system', (exist) ->
                exist.should.equal false
                done()

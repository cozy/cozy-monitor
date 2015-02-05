stackApplication = require '../lib/stack_application'
monitoring = require '../lib/monitoring'
should = require('chai').should()
fs = require 'fs'

SECOND = 1000
MINUTE = 60 * SECOND

describe "Monitoring", ->
    before (done) ->
        @timeout 2 * MINUTE
        stackApplication.install 'data-system', {}, (err) ->
            stackApplication.install 'home', {}, (err) ->
                stackApplication.install 'proxy', {}, (err) ->
                    done()

    after (done) ->
        @timeout 2 * MINUTE
        stackApplication.uninstall 'data-system', (err) ->
            stackApplication.uninstall 'home', (err) ->
                stackApplication.uninstall 'proxy', (err) ->
                    done()

    describe "Routes", ->

        describe "Get all routes", ->
            it "When I send a request to add dev route", (done) ->
                monitoring.getRoutes (err, routes) =>
                    @err = err
                    @routes = routes
                    done()

            it "Then error should not exist", ->
                should.not.exist @err

            it "And there is no routes",  ->
                Object.keys(@routes).length.should.equal 0

        describe "Add dev route", ->
            it "When I send a request to add dev route", (done) ->
                monitoring.startDevRoute 'test', 9915, (err) =>
                    @err = err
                    done()

            it "Then error should not exist", ->
                should.not.exist @err

            it "And route should be added", (done) ->
                monitoring.getRoutes (err, routes) =>
                    routes.test.should.exist
                    done()

        describe "Remove dev route", ->
            it "When I send a request to stop dev route", (done) ->
                monitoring.stopDevRoute 'test', (err) =>
                    @err = err
                    done()

            it "Then error should not exist", ->
                should.not.exist @err

            it "And route should be removed", (done) ->
                monitoring.getRoutes (err, routes) =>
                    Object.keys(routes).length.should.equal 0
                    done()

    describe 'Status', ->

        describe "Get status for application started", ->
            it "When I send a request to get proxy status", (done) ->
                monitoring.moduleStatus 'proxy', (status) =>
                    @status = status
                    done()

            it "And status should be up", ->
                @status.should.equal 'up'

        describe "Get status for application stopped", ->
            it "When I send a request to get status", (done) ->
                stackApplication.stop 'home', (err) =>
                    monitoring.moduleStatus 'home', (status) =>
                        @status = status
                        done()

            it "And status should be down", ->
                @status.should.equal 'down'

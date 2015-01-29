fs = require "fs"
log = require('printit')()

couchUrl = "http://localhost:5984/"
dataSystemUrl = "http://localhost:9101/"
indexerUrl = "http://localhost:9102/"
controllerUrl = "http://localhost:9002/"
homeUrl = "http://localhost:9103/"
proxyUrl = "http://localhost:9104/"
postfixUrl = "http://localhost:25/"
ControllerClient = require("cozy-clients").ControllerClient

module.exports.homeClient = request.newClient homeUrl
module.exports.statusClient = request.newClient ''
module.exports.couchClient = request.newClient couchUrl
module.exports.dsClient = request.newClient dataSystemUrl

token = getToken()
module.exports.client = new ControllerClient
    token: token


# Generate a random 32 char string.
module.exports.randomString = (length=32) ->
    string = ""
    string += Math.random().toString(36).substr(2) while string.length < length
    string.substr 0, length


# Read Controller auth token from token file located in /etc/cozy/stack.token .
module.exports.readToken = (file) ->
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


# Get Controller auth token from token file. If it can't find token in
# expected folder it looks for in the location of previous controller version
# (backward compatibility).
module.exports.getToken = ->
    # New controller
    if fs.existsSync '/etc/cozy/stack.token'
        return readToken '/etc/cozy/stack.token'
    else
        # Old controller
        if fs.existsSync '/etc/cozy/controller.token'
            return readToken '/etc/cozy/controller.token'
        else
            return null


module.exports.getAuthCouchdb = (callback) ->
    try
        data = fs.readFileSync '/etc/cozy/couchdb.login', 'utf8', (err, data) =>
        username = data.split('\n')[0]
        password = data.split('\n')[1]
        return [username, password]
    catch err
        console.log err
        log.error """
Cannot read database credentials in /etc/cozy/couchdb.login.
"""
        process.exit 1


module.exports.handleError = (err, body, msg) ->
    log.error "An error occured:"
    log.raw err if err
    log.raw msg
    if body?
        if body.msg?
            log.raw body.msg
        else if body.error?
            log.raw body.error.message if body.error.message?
            log.raw body.message if body.message?
            log.raw body.error.result if body.error.result?
            log.raw "Request error code #{body.error.code}" if body.error.code?
            log.raw body.error.blame if body.error.blame?
            log.raw body.error if typeof body.error is "string"
        else log.raw body
    process.exit 1
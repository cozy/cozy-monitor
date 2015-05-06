fs = require "fs"
log = require('printit')()
request = require("request-json-light")

couchdbHost = process.env.COUCH_HOST or 'localhost'
couchdbPort = process.env.COUCH_PORT or '5984'
indexerHost = process.env.INDEXER_HOST or 'localhost'
indexerPort = process.env.INDEXER_PORT or '9102'
postfixHost = process.env.POSTFIX_HOST or 'localhost'
postfixPort = process.env.POSTFIX_PORT or '25'

couchUrl = "http://#{couchdbHost}:#{couchdbPort}/"
dataSystemUrl = "http://localhost:9101/"
indexerUrl = "http://#{indexerHost}:#{indexerPort}/"
controllerUrl = "http://localhost:9002/"
homeUrl = "http://localhost:9103/"
proxyUrl = "http://localhost:9104/"
postfixUrl = "http://#{postfixHost}:#{postfixPort}/"
ControllerClient = require("cozy-clients").ControllerClient


# Read Controller auth token from token file located in /etc/cozy/stack.token .
readToken = (file) ->
    if process.env.TOKEN?
        return process.env.TOKEN
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
getToken = module.exports.getToken = ->
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

module.exports.makeError = (err, body) ->
    if err?
        return new Error(err)
    else if body?
        if body.msg
            return new Error(body.msg)
        else if body.message
            return new Error(body.message)
        else if body.error
            return new Error(body.error)

module.exports.logError = (err, msg) ->
    log.error "An error occured:"
    log.error msg if msg?
    log.raw err
    process.exit(1)

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


token = getToken()
module.exports.clients =
    'home': request.newClient homeUrl
    'couch': request.newClient couchUrl
    'ds': request.newClient dataSystemUrl
    'index': request.newClient indexerUrl
    'proxy': request.newClient proxyUrl
    'controller': new ControllerClient(token: token)
    'postfix': request.newClient postfixUrl
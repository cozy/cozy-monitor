fs = require 'fs'
tar = require 'tar-stream'
zlib = require 'zlib'
async = require 'async'
request = require 'request-json-light'
vcardParser = require 'cozy-vcard'
log = require('printit')()

helpers = require './helpers'
couchClient = helpers.clients.couch
couchClient.headers['content-type'] = 'application/json'
locale = 'en'


configureCouchClient = ->
    [username, password] = helpers.getAuthCouchdb()
    # Only set auth if database has a password
    if username or password
        couchClient.setBasicAuth username, password


getFiles = (couchClient, callback) ->
    couchClient.get 'cozy/_design/file/_view/byfolder', (err, res, body) ->
        callback err, body

getDirs = (couchClient, callback) ->
    couchClient.get 'cozy/_design/folder/_view/byfolder', (err, res, body) ->
        callback err, body

getAllElements = (couchClient, element, callback) ->
    couchClient.get "cozy/_design/#{element}/_view/all", (err, res, body) ->
        callback err, body

getContent = (couchClient, binaryId, type, callback) ->
    couchClient.saveFileAsStream "cozy/#{binaryId}/file", (err, stream) ->
        if err?
            callback err
        else if stream.statusCode is 404
            couchClient.saveFileAsStream "cozy/#{binaryId}/raw", (err, raw) ->
                if err?
                    callback err
                else
                    raw.on 'error', (err) -> log.error err
                    callback null, raw
        else
            stream.on 'error', (err) -> log.error err
            callback null, stream


createDir = (pack, name, callback) ->
    pack.entry {
        name: name
        mode: 0o750
        type: 'directory'
    }, callback

# Warning: we don't stream but use a buffer because we need the exact size for
# the tarball header before starting to write data, and the size from couchdb
# is not always reliable.
createFileStream = (pack, name, stream, callback) ->
    chunks = []
    stream.on 'error', (err) -> callback err
    stream.on 'data', (chunk) -> chunks.push chunk
    stream.on 'end', ->
        buf = Buffer.concat chunks
        entry = pack.entry({
            name: name
            size: Buffer.byteLength(buf, 'binary')
            mode: 0o640
            mtime: new Date
            type: 'file'
        }, callback)
        entry.write buf
        entry.end()

createMetadata = (pack, name, data, callback) ->
    entry = pack.entry({
        name: name
        size: Buffer.byteLength(data, 'utf8')
        mode: 0o640
        mtime: new Date
        type: 'file'
    }, callback)
    entry.write data
    entry.end()


exportDirs = (pack, next) ->
    getDirs couchClient, (err, dirs) ->
        return next err if err?
        return next null unless dirs?.rows?
        async.eachOf dirs.rows, (dir, key, cb) ->
            createDir pack, "files/#{dir.value.path}/#{dir.value.name}", cb
        , (err) ->
            if err
                log.info 'Error while exporting directories: ', err
            else
                log.info 'Directories have been exported successfully'
            next err

exportFiles = (pack, next) ->
    getFiles couchClient, (err, files) ->
        return next err if err?
        return next null unless files?.rows?
        async.eachSeries files.rows, (file, cb) ->
            binaryId = file?.value?.binary?.file?.id
            return cb() unless binaryId?
            getContent couchClient, binaryId, 'file', (err, stream) ->
                return cb err if err?
                name = "files/#{file.value.path}/#{file.value.name}"
                createFileStream pack, name, stream, cb
        , (err, value) ->
            if err
                log.info 'Error while exporting files: ', err
            else
                log.info 'Files have been exported successfully'
            next err

fetchLocale = (next) ->
    getAllElements couchClient, 'cozyinstance', (err, instance) ->
        locale = instance?.rows?[0].value?.locale || 'en'
        next null

exportPhotos = (pack, references, next) ->
    getAllElements couchClient, 'photo', (err, photos) ->
        return next err if err?
        return next null unless photos?.rows?
        dirname = 'Uploaded from Cozy Photos/'
        dirname = 'Transférées depuis Cozy Photos/' if locale is 'fr'
        dir = "files/Photos/#{dirname}"
        createDir pack, dir, ->
            async.eachSeries photos.rows, (photo, cb) ->
                info = photo?.value
                binaryId = (info?.binary?.raw || info?.binary?.file)?.id
                return cb() unless binaryId?
                name = info.title || (info._id + ".jpg")
                data =
                    albumid: info.albumid
                    filepath: "Photos/#{dirname}/#{name}"
                references.push JSON.stringify(data)
                getContent couchClient, binaryId, 'raw', (err, stream) ->
                    return cb err if err?
                    createFileStream pack, "#{dir}/#{name}", stream, cb
            , (err, value) ->
                if err
                    log.info 'Error while exporting photos: ', err
                else
                    log.info 'Photos have been exported successfully'
                next err

exportAlbums = (pack, references, next) ->
    getAllElements couchClient, 'album', (err, albums) ->
        return next err if err?
        return next null unless albums?.rows?
        albumsref = ''
        async.eachSeries albums.rows, (album, cb) ->
            return cb() unless album?.value?
            id = album.value._id
            rev = album.value._rev
            name = album.value.title
            data =
                _id: album.value._id
                _rev: album.value._rev
                name: album.value.title
                type: 'io.cozy.photos.albums'
            albumsref += JSON.stringify(data) + '\n'
            cb()
        , (err, value) ->
            if err?
                log.info 'Error while exporting albums', err
                return next err
            createDir pack, 'albums', (err) ->
                return next err if err?
                createMetadata pack, 'albums/albums.json', albumsref, (err) ->
                    return next err if err?
                    ref = references.join('\n')
                    createMetadata pack, 'albums/references.json', ref, (err) ->
                        if err?
                            log.info 'Error while exporting albums: ', err
                        else
                            log.info 'Albums have been exported successfully'
                        next err

exportContacts = (pack, next) ->
    getAllElements couchClient, 'contact', (err, contacts) ->
        return next err if err?
        return next null unless contacts?.rows?
        createDir pack, 'contacts', ->
            async.eachSeries contacts.rows, (contact, cb) ->
                return cb() unless contact?.value?
                vcard = vcardParser.toVCF contact.value
                n = contact.value.n
                n = n.replace /;+|-/g, '_'
                filename = "Contact_#{n}.vcf"
                createMetadata pack, "contacts/#{filename}", vcard, cb
            , (err, value) ->
                if err
                    log.info 'Error while exporting contacts: ', err
                else
                    log.info 'Contacts have been exported successfully'
                next err


module.exports.exportDoc = (filename, callback) ->
    configureCouchClient()
    pack = tar.pack()
    pack.on 'error', (err) -> log.error err
    gzip = zlib.createGzip
        level: 6
        memLevel: 6
    gzip.on 'error', (err) -> log.error err
    tarball = fs.createWriteStream filename
    tarball.on 'error', callback
    tarball.on 'close', callback
    pack.pipe(gzip).pipe(tarball)
    references = []
    async.series [
        (next) -> exportDirs(pack, next)
        (next) -> exportFiles(pack, next)
        (next) -> fetchLocale(next)
        (next) -> exportPhotos(pack, references, next)
        (next) -> exportAlbums(pack, references, next)
        (next) -> exportContacts(pack, next)
    ], (err) ->
        if err?
            callback err
        else
            pack.finalize()

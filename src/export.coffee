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
        else
            stream.on 'error', (err) -> log.error err
            callback null, stream


createDir = (pack, dirInfo, callback) ->
    pack.entry {
        name: dirInfo.path + '/' + dirInfo.name
        mode: 0o755
        type: 'directory'
    }, callback

# Warning: we don't stream but use a buffer because we need the exact size for
# the tarball header before starting to write data, and the size from couchdb
# is not always reliable.
createFileStream = (pack, fileInfo, stream, callback) ->
    chunks = []
    stream.on 'error', (err) -> callback err
    stream.on 'data', (chunk) -> chunks.push chunk
    stream.on 'end', ->
        buf = Buffer.concat chunks
        entry = pack.entry({
            name: fileInfo.path + '/' + fileInfo.name
            size: Buffer.byteLength(buf, 'binary')
            mode: 0o755
            mtime: new Date
            type: fileInfo.docType.toLowerCase()
        }, callback)
        entry.write buf
        entry.end()

createPhotos = (pack, photoInfo, photopath, stream, callback) ->
    chunks = []
    stream.on 'error', (err) -> callback err
    stream.on 'data', (chunk) -> chunks.push chunk
    stream.on 'end', ->
        buf = Buffer.concat chunks
        entry = pack.entry({
            name: photopath + photoInfo.title
            size: Buffer.byteLength(buf, 'binary')
            mode: 0o755
            mtime: new Date
            type: 'file'
        }, callback)
        entry.write buf
        entry.end()

createMetadata = (pack, data, dst, filename, callback) ->
    entry = pack.entry({
        name: dst + filename
        size: Buffer.byteLength(data, 'utf8')
        mode: 0o755
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
            createDir pack, dir.value, cb
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
            fileInfo = file?.value
            getContent couchClient, binaryId, 'file', (err, stream) ->
                return cb err if err?
                createFileStream pack, fileInfo, stream, cb
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
        name = 'Uploaded from Cozy Photos/'
        if locale is 'fr'
            name = 'Transférées depuis Cozy Photos/'
        path = '/Photos/' + name
        dirInfo =
            path: '/Photos'
            name: name
        createDir pack, dirInfo, ->
            async.eachSeries photos.rows, (photo, cb) ->
                info = photo?.value
                info.title ||= info._id + ".jpg"
                binaryId = (info?.binary?.raw || info?.binary?.file)?.id
                return cb() unless binaryId?
                data =
                    albumid: info.albumid
                    filepath: path + info.title
                references.push JSON.stringify(data)
                getContent couchClient, binaryId, 'raw', (err, stream) ->
                    return cb err if err?
                    createPhotos pack, info, path, stream, cb
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
            dirInfo =
                path: '/metadata'
                name: 'album/'
            createDir pack, dirInfo, (err) ->
                return next err if err?
                createMetadata pack, albumsref, '/metadata/album/', 'album.json', (err) ->
                    return next err if err?
                    createMetadata pack, references.join('\n'), '/metadata/album/', 'references.json', (err) ->
                        if err?
                            log.info 'Error while exporting albums: ', err
                        else
                            log.info 'Albums have been exported successfully'
                        next err

exportContacts = (pack, next) ->
    getAllElements couchClient, 'contact', (err, contacts) ->
        return next err if err?
        return next null unless contacts?.rows?
        dirInfo =
            path: '/metadata'
            name: 'contact/'
        createDir pack, dirInfo, ->
            async.eachSeries contacts.rows, (contact, cb) ->
                return cb() unless contact?.value?
                vcard = vcardParser.toVCF contact.value
                n = contact.value.n
                n = n.replace /;+|-/g, '_'
                filename = "Contact_#{n}.vcf"
                createMetadata pack, vcard, '/metadata/contact/', filename, cb
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

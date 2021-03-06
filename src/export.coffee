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


createViews = (callback) ->
    views =
        views:
            files:
                map: "
function (doc) {
  if (doc.docType && doc.docType.toLowerCase() === 'file') {
    emit(doc.path, doc)
  }
}"
            folders:
                map: "
function (doc) {
  if (doc.docType && doc.docType.toLowerCase() === 'folder') {
    emit(doc.path, doc)
  }
}"
    couchClient.put 'cozy/_design/cozy-monitor-export', views, callback


getFiles = (couchClient, callback) ->
    couchClient.get 'cozy/_design/cozy-monitor-export/_view/files', (err, res, body) ->
        if err
            callback err
        else if res.statusCode isnt 200
            callback "status code #{res.statusCode} for files"
        else
            callback null, body

getDirs = (couchClient, callback) ->
    couchClient.get 'cozy/_design/cozy-monitor-export/_view/folders', (err, res, body) ->
        if err
            callback err
        else if res.statusCode isnt 200
            callback "status code #{res.statusCode} for folders"
        else
            callback null, body

getAllElements = (couchClient, element, callback) ->
    couchClient.get "cozy/_design/#{element}/_view/all", (err, res, body) ->
        if err
            callback err
        else if res.statusCode isnt 200
            callback "status code #{res.statusCode} for #{element}"
        else
            callback null, body

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

allDocuments = (couchClient, start, forEach, done) ->
    limit = 1000
    u = "cozy/_all_docs?include_docs=true&limit=#{limit}"
    u += "&skip=1&startkey=\"#{encodeURIComponent start}\"" if start?
    couchClient.get u, (err, res, body) ->
        if err?
            done err
        else
            async.eachSeries body.rows, (row, cb) ->
                forEach row.doc, cb
            , (err) ->
                if err
                    done err
                else if body.rows.length == limit
                    start = body.rows[limit-1].id
                    allDocuments couchClient, start, forEach, done
                else
                    done null



createDir = (pack, name, callback) ->
    pack.entry {
        name: name
        mode: 0o750
        type: 'directory'
    }, callback

# Warning: we don't stream but use a buffer because we need the exact size for
# the tarball header before starting to write data, and the size from couchdb
# is not always reliable. Except when the file is big (more than 0.5GB) and
# buffering it may take too much memory.
createFileStream = (pack, name, size, stream, callback) ->
    if +size > 500000000
        stream.pipe pack.entry({
            name: name
            size: size
            mode: 0o640
            mtime: new Date
            type: 'file'
        }, callback)
    else
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

createFile = (pack, name, data, callback) ->
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
        async.eachSeries dirs.rows, (dir, cb) ->
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
                size = file?.value?.size
                createFileStream pack, name, size, stream, cb
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
        return next null if err is "status code 404 for photo"
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
                    createFileStream pack, "#{dir}/#{name}", 0, stream, cb
            , (err, value) ->
                if err
                    log.info 'Error while exporting photos: ', err
                else
                    log.info 'Photos have been exported successfully'
                next err

exportAlbums = (pack, references, next) ->
    getAllElements couchClient, 'album', (err, albums) ->
        return next null if err is "status code 404 for album"
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
                name: album.value.title || album.id
                type: 'io.cozy.photos.albums'
            albumsref += JSON.stringify(data) + '\n'
            cb()
        , (err, value) ->
            if err?
                log.info 'Error while exporting albums', err
                return next err
            createDir pack, 'albums', (err) ->
                return next err if err?
                createFile pack, 'albums/albums.json', albumsref, (err) ->
                    return next err if err?
                    ref = references.join('\n')
                    createFile pack, 'albums/references.json', ref, (err) ->
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
                n = contact.value.n || contact.id
                n = n.replace /;+|-/g, '_'
                filename = "Contact_#{n}.vcf"
                createFile pack, "contacts/#{filename}", vcard, cb
            , (err, value) ->
                if err
                    log.info 'Error while exporting contacts: ', err
                else
                    log.info 'Contacts have been exported successfully'
                next err


exportOthers = (pack, next) ->
    doctypes = {}
    other = "Archive"
    saveFile = (doc, doctype, callback) ->
        name = "files/#{other}/#{doctype}/#{doc._id}"
        data = JSON.stringify doc
        createFile pack, name, data, callback
    save = (doc, callback) ->
        return callback() unless doc.docType?
        doctype = doc.docType.toLowerCase()
        return callback() if doctype == "file" || doctype == "folder"
        return callback() if doctype == "binary" || doctype == "contact"
        return callback() if doctype == "album" || doctype == "photo"
        if doctypes[doctype]
            saveFile doc, doctype, callback
        else
            doctypes[doctype] = true
            createDir pack, "files/#{other}/#{doctype}", (err) ->
                if err?
                    callback err
                else
                    saveFile doc, doctype, callback
    allDocuments couchClient, null, save, (err) ->
        if err?
            log.info 'Error while exporting other doctypes: ', err
        else
            log.info 'Other doctypes have been exported successfully'
        next err



module.exports.exportDoc = (filename, callback) ->
    configureCouchClient()
    pack = tar.pack()
    pack.on 'error', (err) -> log.error err
    gzip = zlib.createGzip
        level: 6
        memLevel: 6
    gzip.on 'error', (err) -> log.error err
    if filename is '-'
        process.env.NODE_ENV = 'test' # XXX hack to avoid logs on stdout
        tarball = process.stdout
    else
        tarball = fs.createWriteStream filename
    tarball.on 'error', callback
    tarball.on 'close', callback
    pack.pipe(gzip).pipe(tarball)
    references = []
    async.series [
        (next) -> createViews(next)
        (next) -> exportDirs(pack, next)
        (next) -> exportFiles(pack, next)
        (next) -> fetchLocale(next)
        (next) -> exportPhotos(pack, references, next)
        (next) -> exportAlbums(pack, references, next)
        (next) -> exportContacts(pack, next)
        (next) -> exportOthers(pack, next)
    ], (err) ->
        if err?
            callback err
        else
            pack.finalize()

fs = require 'fs'
tar = require 'tar-stream'
zlib = require 'zlib'
gzip = zlib.createGzip
    level: 6
    memLevel: 6

async = require 'async'
request = require 'request-json-light'
vcardParser = require 'cozy-vcard'
log = require('printit')()

helpers = require './helpers'
couchClient = helpers.clients.couch
couchClient.headers['content-type'] = 'application/json'

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

getPhotoLength = (couchClient, binaryId, callback) ->
    couchClient.get 'cozy/' + binaryId, (err, res, body) ->
        callback err, body?._attachments?.raw?.length

getContent = (couchClient, binaryId, type, callback) ->
    couchClient.saveFileAsStream "cozy/#{binaryId}/#{type}", (err, stream) ->
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

createFileStream = (pack, fileInfo, stream, callback) ->
    stream.pipe pack.entry({
        name: fileInfo.path + '/' + fileInfo.name
        size: fileInfo.size
        mode: 0o755
        mtime: new Date
        type: fileInfo.docType
    }, callback)

createPhotos = (pack, photoInfo, photopath, stream, size, callback) ->
    stream.pipe pack.entry({
        name: photopath + photoInfo.title
        size: size
        mode: 0o755
        mtime: new Date
        type: 'file'
    }, callback)

createMetadata = (pack, data, dst, filename, callback) ->
    entry = pack.entry({
        name: dst + filename
        size: data.length
        mode: 0o755
        mtime: new Date
        type: 'file'
    }, callback)
    entry.write data
    entry.end()

module.exports.exportDoc = (filename, callback) ->
    configureCouchClient()
    pack = tar.pack()
    tarball = fs.createWriteStream filename
    pack.pipe(gzip).on('error', (err) ->
        log.error err
    ).pipe(tarball).on('error', (err) ->
        log.error err
    )
    references = ''
    locale = 'en'
    async.series [

        # 1. export and create dirs
        (next) ->
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

        # 2. export and create files
        (next) ->
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

        # 3. fetch the locale
        (next) ->
            getAllElements couchClient, 'cozyinstance', (err, instance) ->
                locale = instance?.rows?[0].value?.locale
                next null

        # 4. export photos
        (next) ->
            getAllElements couchClient, 'photo', (err, photos) ->
                return next err if err?
                return next null unless photos?.rows?
                name = 'Uploaded from Cozy Photos/'
                photopath = '/Photos/' + name
                if locale is 'fr'
                    name = 'Transférées depuis Cozy Photos/'
                dirInfo =
                    path: '/Photos'
                    name: name
                createDir pack, dirInfo, ->
                    async.eachSeries photos.rows, (photo, cb) ->
                        binaryId = photo?.value?.binary?.raw?.id
                        return cb() unless binaryId?
                        photoInfo = photo?.value
                        data =
                            albumid: photoInfo.albumid
                            filepath: photopath + photoInfo.title
                        references += JSON.stringify(data) + '\n'
                        getContent couchClient, binaryId, 'raw', (err, stream) ->
                            return cb err if err?
                            getPhotoLength couchClient, binaryId, (err, size) ->
                                return cb err if err?
                                createPhotos pack, photoInfo, photopath, stream, size, cb
                    , (err, value) ->
                        if err
                            log.info 'Error while exporting photos: ', err
                        else
                            log.info 'Photos have been exported successfully'
                        next err

        # 5. export albums
        (next) ->
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
                            createMetadata pack, references, '/metadata/album/', 'references.json', (err) ->
                                if err?
                                    log.info 'Error while exporting albums: ', err
                                else
                                    log.info 'Albums have been exported successfully'
                                next err

        # 6. export contacts
        (next) ->
            getAllElements couchClient, 'contact', (err, contacts) ->
                return next err if err?
                return next null unless contacts?.rows?
            dirInfo =
                path: '/metadata'
                name: 'contact/'
            createDir pack, dirInfo, ->
                async.eachSeries contacts.rows, (contact, next) ->
                    return next() unless contact?.value?
                    vcard = vcardParser.toVCF contact.value
                    n = contact.value.n
                    n = n.replace /;+|-/g, '_'
                    filename = "Contact_#{n}.vcf"
                    createMetadata pack, vcard, '/metadata/contact/', filename, next
                , (err, value) ->
                    if err
                        log.info 'Error while exporting contacts: ', err
                    else
                        log.info 'Contacts have been exported successfully'
                    next err

    ], (err, value) ->
        if err?
            callback err
        else
            pack.finalize()
            callback()

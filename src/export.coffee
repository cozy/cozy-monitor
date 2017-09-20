program = undefined
fs = undefined
tar = undefined
zlib = undefined
log = undefined
helpers = undefined
asyn = undefined
request = undefined
VCardParser = undefined
gunzip = undefined
couchClient = undefined
getFiles = undefined
getDirs = undefined
getAllElements = undefined
getPhotoLength = undefined
getContent = undefined
createDir = undefined
createFileStream = undefined
createPhotos = undefined
createMetadata = undefined
createAlbums = undefined
exportDoc = undefined
program = require('commander')
fs = require('fs')
tar = require('tar-stream')
zlib = require('zlib')
gzip = zlib.createGzip(
  level: 6
  memLevel: 6)
log = require('printit')()
helpers = require('./helpers')
asyn = require('async')
request = require('request-json-light')
VCardParser = require('cozy-vcard')
couchClient = helpers.clients.couch
couchClient.headers['content-type'] = 'application/json'

getFiles = (couchClient, callback) ->
  couchClient.get 'cozy/_design/file/_view/byfolder', (err, res, body) ->
    if err != null
      callback err, null
    else
      callback null, body

getDirs = (couchClient, callback) ->
  couchClient.get 'cozy/_design/folder/_view/byfolder', (err, res, body) ->
    if err != null
      callback err, null
    else
      callback null, body

getAllElements = (couchClient, element, callback) ->
  couchClient.get 'cozy/_design/' + element + '/_view/all', (err, res, body) ->
    if err != null
      callback err, null
    else
      callback null, body

getPhotoLength = (couchClient, binaryId, callback) ->
  couchClient.get 'cozy/' + binaryId, (err, res, body) ->
    if err != null
      callback err, null
    else
      if body and body._attachments and body._attachments.raw and body._attachments.raw.length
        callback null, body._attachments.raw.length
      else
        callback null, null

getContent = (couchClient, binaryId, type, callback) ->
  couchClient.saveFileAsStream 'cozy/' + binaryId + '/' + type, (err, stream) ->
    if err != null
      callback err, null
    else
      callback null, stream

createDir = (pack, dirInfo, callback) ->
  pack.entry {
    name: dirInfo.path + '/' + dirInfo.name
    mode: 0755
    type: 'directory'
  }, callback
  return

createFileStream = (pack, fileInfo, stream, callback) ->
  stream.pipe pack.entry({
    name: fileInfo.path + '/' + fileInfo.name
    size: fileInfo.size
    mode: 0755
    mtime: new Date
    type: fileInfo.docType
  }, ->
    callback.apply null, arguments
    return
  )
  return

createPhotos = (pack, photoInfo, photopath, stream, size, callback) ->
  stream.pipe pack.entry({
    name: photopath + photoInfo.title
    size: size
    mode: 0755
    mtime: new Date
    type: 'file'
  }, ->
    callback.apply null, arguments
    return
  )
  return

createMetadata = (pack, data, dst, filename, callback) ->
  entry = pack.entry({
    name: dst + filename
    size: data.length
    mode: 0755
    mtime: new Date
    type: 'file'
  }, ->
    callback.apply null, arguments
  )
  entry.write data
  entry.end()
  return

exportDoc =
module.exports.exportDoc = (couchClient, callback) ->
  pack = tar.pack()
  tarball = fs.createWriteStream('cozy.tar.gz')
  pack.pipe(gzip).on('error', (err) ->
    console.error err
    return
  ).pipe(tarball).on 'error', (err) ->
    console.error err
    return
  references = ''
  asyn.series [
    (callback) ->
      #export and create dirs
      getDirs couchClient, (err, dirs) ->
        if err != null
          return callback(err, null)
        if !dirs.rows
          return null
          null

        asyn.eachOf dirs.rows, (dir, callback) ->
          if dir.value
            createDir pack, dir.value, callback
          return
        return
      log.info 'All directories have been exported successfully'
      callback null, 'one'
      return
    (callback) ->
      # export and create files
      getFiles couchClient, (err, files) ->
        if err != null
          return callback(err, null)
        if !files.rows
          return null
          null

        asyn.eachSeries files.rows, ((file, callback) ->
          if file.value and file.value.binary and file.value.binary.file.id
            binaryId = file.value.binary.file.id
            fileInfo = file.value
            getContent couchClient, binaryId, 'file', (err, stream) ->
              createFileStream pack, fileInfo, stream, callback
              return
          return
        ), (err, value) ->
          if err != null
            return callback(err, null)
          log.info 'All files have been exported successfully'
          callback null, 'two'
        return
      return
    (callback) ->
      # export photos 
      getAllElements couchClient, 'photo', (err, photos) ->
        if err != null
          return callback(err, null)
        if !photos.rows
          return null
          null

        getAllElements couchClient, 'cozyinstance', (err, instance) ->
          if err != null
            return callback(err, null)
          if instance.rows
            instanceInfo = instance.rows[0]
            name = 'Uploaded from Cozy Photos/'
            photopath = '/Photos/' + name
            if instanceInfo.value and instanceInfo.value.docType == 'cozyinstance' and instanceInfo.value.locale == 'fr'
              name = 'Transferees depuis Cozy Photos/'
              photopath = '/Photos/' + name
            dirInfo = 
              path: '/Photos'
              name: name
            createDir pack, dirInfo, ->
              asyn.eachSeries photos.rows, ((photo, callback) ->
                if photo.value and photo.value.binary and photo.value.binary.raw.id
                  binaryId = photo.value.binary.raw.id
                  photoInfo = photo.value
                  data = 
                    albumid: photoInfo.albumid
                    filepath: photopath + photoInfo.title
                  references += JSON.stringify(data) + '\n'
                  getContent couchClient, binaryId, 'raw', (err, stream) ->
                    getPhotoLength couchClient, binaryId, (err, size) ->
                      if err != null
                        return callback(err, null)
                      if size != null
                        createPhotos pack, photoInfo, photopath, stream, size, callback
                      return
                    return
                return
              ), (err, value) ->
                if err != null
                  console.log 'error photo'
                  return callback(err, null)
                log.info 'All photos have been exported successfully'
                callback null, 'three'
              return
          return
        return
      return
    (callback) ->
      #export album
      getAllElements couchClient, 'album', (err, albums) ->
        if err != null
          return callback(err, null)
        if !albums.rows
          return null
          null

        albumsref = ''
        asyn.eachSeries albums.rows, ((album, callback) ->
          if album.value and album.value.title
            id = album.value._id
            rev = album.value._rev
            name = album.value.title
            data = 
              _id: id
              _rev: rev
              name: name
              type: 'io.cozy.photos.albums'
            albumsref += JSON.stringify(data) + '\n'
          callback()
          return
        ), (err, value) ->
          if err != null
            console.log 'error albums'
            return callback(err, null)
          dirInfo = 
            path: '/metadata'
            name: 'album/'
          createDir pack, dirInfo, ->
            createMetadata pack, albumsref, '/metadata/album/', 'album.json', ->
              createMetadata pack, references, '/metadata/album/', 'references.json', ->
                log.info 'All albums have been exported successfully'
                callback null, 'four'
              return
            return
          return
        return
      return
    (callback) ->
      #export contacts
      getAllElements couchClient, 'contact', (err, contacts) ->
        if err != null
          return callback(err, null)
        if !contacts.rows
          return null
          null

        dirInfo = 
          path: '/metadata'
          name: 'contact/'
        createDir pack, dirInfo, ->
          asyn.eachSeries contacts.rows, ((contact, callback) ->
            if contact.value and contact.value.n
              vcard = VCardParser.toVCF(contact.value)
              n = contact.value.n
              n = n.replace(/;+|-/g, '_')
              filename = 'Contact_' + n + '.vcf'
              createMetadata pack, vcard, '/metadata/contact/', filename, callback
            return
          ), (err, value) ->
            if err != null
              return callback(err, null)
            log.info 'All contacts have been exported successfully'
            callback null, 'five'
            return
          return
        return
      return
  ], (err, value) ->
    if err != null
      err
      null
    else
      pack.finalize()
      null
      value
  callback null, null

exportDoc couchClient, (err, ok) ->
  if err != null
    err
  else
    ok

# ---
# generated by js2coffee 2.2.0

var program, fs, tar, zlib, log, helpers, asyn, request, gunzip, couchClient, getFiles, getDirs, getPhotos, getPhotoLength, getAlbums, getContent, createDir, createFileStream, createPhotos, createMetadata, createAlbums, exportDoc;

program = require('commander');

fs = require('fs');

tar = require('tar-stream');

zlib = require('zlib');
var gzip = zlib.createGzip({level:6, memLevel:6});

log = require('printit')();

helpers = require('./helpers');

asyn = require('async');

request = require('request-json-light');

couchClient = helpers.clients.couch;
couchClient.headers['content-type'] = 'application/json';

getFiles = function(couchClient, callback) {

	return couchClient.get('cozy/_design/file/_view/byfolder', function(err, res, body) {
		if (err != null) {
			return callback(err, null);
		} else {
			return callback(null, body);
		}
	});
};

getDirs = function(couchClient, callback) {

    return couchClient.get('cozy/_design/folder/_view/byfolder', function(err, res, body) {
        if (err != null) {
            return callback(err, null);
        } else {
            return callback(null, body);
        }
    });
};

getPhotos = function(couchClient, callback) {

    return couchClient.get('cozy/_design/photo/_view/all', function(err, res, body) {
        if (err != null) {
            return callback(err, null);
        } else {
            return callback(null, body);
        }
    });
};

getPhotoLength = function(couchClient, binaryId, callback) {

    return couchClient.get('cozy/' + binaryId, function(err, res, body) {
        if (err != null) {
            return callback(err, null);
        } else {
            if (body && body._attachments && body._attachments.raw && body._attachments.raw.length){
                return callback(null, body._attachments.raw.length);
            }else{
                return callback(null, null)
            }
        }
    });
};

getAlbums = function(couchClient, callback) {

    return couchClient.get('cozy/_design/album/_view/all', function(err, res, body) {
        if (err != null) {
            return callback(err, null);
        } else {
            return callback(null, body);
        }
    });
};

getContent = function(couchClient, binaryId, type, callback) {

	return couchClient.saveFileAsStream('cozy/'+ binaryId + "/" + type, function(err, stream) {
		if (err != null) {
			return callback(err, null);
		} else {
			return callback(null, stream);
		}
	});
};

createDir = function(pack, dirInfo, callback) {

    pack.entry({
        name: dirInfo.path + "/" + dirInfo.name, 
        mode: 0755,
        type: 'directory'
    }, callback);

};

createFileStream = function(pack, fileInfo, stream, callback) {

	stream.pipe(pack.entry({ 
		name: fileInfo.path + "/" + fileInfo.name,
		size: fileInfo.size, 
		mode: 0755, 
		mtime: new Date(), 
		type: fileInfo.docType
	}, function(){
		callback.apply(null, arguments)
	}))
};

createPhotos = function(pack, photoInfo, stream, size, callback) {

    stream.pipe(pack.entry({ 
        name: "Photos/Uploaded from Cozy Photos/" + photoInfo.title,
        size: size,
        mode: 0755, 
        mtime: new Date(), 
        type: 'file'
    }, function(){
        callback.apply(null, arguments)
    }))
};

createMetadata = function(pack, data, filename, callback){

    var entry = pack.entry({ 
        name: 'metadata/album/' + filename,
        size: data.length,
        mode: 0755, 
        mtime: new Date(), 
        type: 'file'
    }, function(){
        return callback.apply(null, arguments)
    })

    entry.write(data)
    entry.end()

}

exportDoc = module.exports.exportDoc = function(couchClient, callback){
	var pack = tar.pack();
	var tarball = fs.createWriteStream('cozy.tar.gz');
	pack.pipe(gzip).on("error", function(err) { console.error(err) })
    .pipe(tarball).on("error", function(err) { console.error(err) })	

    asyn.series([ function(callback){

    //export and create dirs
    getDirs(couchClient, function(err, dirs){
    	if (err != null) {
    		return callback(err, null);
    	}
    	if (!dirs.rows) {return null, null};
    	asyn.eachOf(dirs.rows, function(dir, callback){
    		if(dir.value){
    			createDir(pack, dir.value, callback);
    		}
    	});
    });
    log.info("All directories have been exported successfully");
    callback(null, "one")
},
function(callback){
    // export and create files
    getFiles(couchClient, function(err, files){
    	if (err != null) {
    		return callback(err, null);
    	} 
    	if (!files.rows) {return null, null};	
    	asyn.eachSeries(files.rows, function(file, callback){
    		if (file.value && file.value.binary && file.value.binary.file.id) {
    			var binaryId = file.value.binary.file.id;
    			var fileInfo = file.value;
    			getContent(couchClient, binaryId, "file", function(err, stream){
    				createFileStream(pack, fileInfo, stream, callback);
    			});
    		}
    	}, function(err, value) {
    		if (err != null) {
    			return callback(err, null);
    		} 
    		log.info("All files have been exported successfully");
    		return callback(null, "two");
    	});

    });
},
function(callback){
    // export photos 
    getPhotos(couchClient, function(err, photos){
        if (err != null){
            return callback(err, null);
        }
        if (!photos.rows) {return null, null};
        var references = "";
        asyn.eachSeries(photos.rows, function(photo, callback){
            if (photo.value && photo.value.binary && photo.value.binary.raw.id) {
                var binaryId = photo.value.binary.raw.id;
                var photoInfo = photo.value;
                var data = {
                    albumid: photoInfo.albumid,
                    filepath: "Photos/Uploaded from Cozy Photos/" + photoInfo.title
                };
                references +=  JSON.stringify(data)+ "\n";
                getContent(couchClient, binaryId, "raw", function(err, stream){
                    getPhotoLength(couchClient, binaryId, function(err, size){
                        if (err != null){
                            return callback(err, null)
                        }
                        if (size != null){
                            createPhotos(pack, photoInfo, stream, size, callback);
                        }                        
                    })
                });
            }
        }, function(err, value) {
            if (err != null) {
                console.log("error photo")
                return callback(err, null);
            }
            createMetadata(pack, references, "references.json", function(){ 
                log.info("All photos have been exported successfully");
                return callback(null, "three");
            })
        });
    });
},function(callback){
    //export album
    getAlbums(couchClient, function(err, albums){
        if (err != null){
            return callback(err, null)
        }
        if (!albums.rows) {return null, null};
        var albumsref = "";
        asyn.eachSeries(albums.rows, function(album, callback){
            if (album.value && album.value.title) {
                var id = album.value._id;
                var rev = album.value._rev;
                var name = album.value.title;
                var data = {
                    _id: id,
                    _rev: rev,
                    name: name,
                    type: "io.cozy.photos.albums"
                }
                albumsref += JSON.stringify(data)+ "\n";
            }
            callback();
        }, function(err, value) {
            if (err != null) {
                console.log("error albums")
                return callback(err, null);
            } 
            createMetadata(pack, albumsref, "album.json", function(){
                log.info("All albums have been exported successfully");
                return callback(null, "four");
            });
            
        });
    })
    
}

], function(err, value){
 if (err != null){
    return err, null
}else{
    pack.finalize()
    return null, value
}
});
return callback(null, null);
};

exportDoc(couchClient, function(err, ok){
    if (err != null){
        return err
    }else{
        return ok
    }
})


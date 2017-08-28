var program, fs, tar, log, helpers, asyn, request, couchClient, exportDoc, getFiles, getContent, createFile, getDirs, createDir, getPhotos, createReferences, getBinaryId;

program = require('commander');

fs = require('fs');

tar = require('tar-stream');

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

getContent = function(couchClient, binaryId, type, callback) {

	return couchClient.saveFileAsStream('cozy/'+ binaryId + "/" + type, function(err, stream) {
		if (err != null) {
			return callback(err, null);
		} else {
			return callback(null, stream);
		}
	});
};

createFile = function(pack, fileInfo, stream, callback) {

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

getDirs = function(couchClient, callback) {

	return couchClient.get('cozy/_design/folder/_view/byfolder', function(err, res, body) {
		if (err != null) {
			return callback(err, null);
		} else {
			return callback(null, body);
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

createReferences = function(pack, photoInfo, callback){
    var data = {
        albumid: photoInfo.albumid,
        filepath: photoInfo.title
    };
    
    var entry = pack.entry({ 
        name: "metadata/album/references.json",
        size: JSON.stringify(data).length + 1,
        mode: 0755, 
        mtime: new Date(), 
        type: "file"
    }, function(){
        return callback.apply(null, arguments)
    })

    entry.write(JSON.stringify(data))
    entry.write("\n")
    entry.end()

}

createPhotos = function(pack, photoInfo, stream, size, callback) {

    stream.pipe(pack.entry({ 
        name: "Photos/Uploaded from Cozy Photos/" + photoInfo.title,
        size: size,
        mode: 0755, 
        mtime: new Date(), 
        type: "file"
    }, function(){
        callback.apply(null, arguments)
    }))
};

exportDoc = module.exports.exportDoc = function(couchClient, callback){
	var pack = tar.pack();
	var tarball = fs.createWriteStream('cozy.tar.gz');
	pack.pipe(tarball);	

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
    				createFile(pack, fileInfo, stream, callback);
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
        asyn.eachSeries(photos.rows, function(photo, callback){
            if (photo.value && photo.value.binary && photo.value.binary.raw.id) {
                var binaryId = photo.value.binary.raw.id;
                var photoInfo = photo.value;
                getContent(couchClient, binaryId, "raw", function(err, stream){
                    getPhotoLength(couchClient, binaryId, function(err, size){
                        if (err != null){
                            return callback(err, null)
                        }
                        if (size != null){
                            createPhotos(pack, photoInfo, stream, size, function(){
                                createReferences(pack, photoInfo, callback);
                            });
                            //stream.on('end', function(){console.log("stream end")})
                        }                        
                    })
                });
            }
        }, function(err, value) {
            if (err != null) {
                console.log("error photo")
                return callback(err, null);
            } 
            log.info("All photos have been exported successfully");
            return callback(null, "three");
        });
    });
}

], function(err, value){
 if (err != null){
  return err, null
}else{
  return null, value
}
});
    return callback(null, null);
};

exportDoc(couchClient, function(err, ok){
    if (err != null){
        return err
    }else{
        console.log(ok);
        return ok
    }

})


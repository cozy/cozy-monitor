var program, fs, tar, log, helpers, asyn, request, couchClient, exportDoc, getFiles, getContent, createFile, getDirs, createDir, getBinaryId;

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
			return callback(err);
		} else {
			return callback(body);
		}
	});
};

getContent = function(couchClient, binaryId, fileInfo, callback) {

	return couchClient.saveFileAsStream('cozy/'+ binaryId + "/file", function(err, stream) {
		if (err != null) {
			return callback(err);
		} else {
			return callback(stream);
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
			return callback(err);
		} else {
			return callback(body);
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

module.exports.exportDoc = function(couchClient, callback){
	var pack = tar.pack();
	var tarball = fs.createWriteStream('cozy.tar.gz');
	pack.pipe(tarball);	


    //export and create dirs
    getDirs(couchClient, function(dirs){
    	if (!dirs.rows) {return null};
    	asyn.eachOf(dirs.rows, function(dir, callback){
    		if(dir.value){
    			createDir(pack, dir.value, callback);
    		}
    	});
    });

    // export and create files
    getFiles(couchClient, function(files){

    	if (!files.rows) {return null};	
    	asyn.eachSeries(files.rows, function(file, callback){
    		if (file.value && file.value.binary && file.value.binary.file.id) {
    			var binaryId = file.value.binary.file.id;
    			var fileInfo = file.value;
    			getContent(couchClient, binaryId, fileInfo, function(stream){
    				createFile(pack, fileInfo, stream, callback);
    			});
    		}
    	}, function(err) {
    		if (err != null) {
    			return callback(err);
    		} 
    		log.info("All files have been exported successfully");
    		return null;
    	});

    });
};



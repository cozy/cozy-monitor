var programme, log, getFiles, getBinaryId, helpers, request;

program = require('commander');

helpers = require('./helpers');

log = require('printit')();

request = require("request-json-light");

couchClient = helpers.clients.couch

getFiles = function(couchClient, callback) {

	return couchClient.get('cozy/_design/file/_view/byfolder', function(err, res, files) {
		if (err) {
			log.raw(err);
			log.error('Cannot retrieve files');
			return process.exit(1);
		} else {
			return callback(files);
		}
	});
};

getBinaryId = function(couchClient, binaryId, callback) {

	return couchClient.get('cozy/'+ binaryId, function(err, res, files) {
		if (err) {
			log.raw(err);
			log.error('Cannot retrieve files');
			return process.exit(1);
		} else {
			return callback(files);
		}
	});
};

getFiles(couchClient, function(files){
	if (!files.rows) {return null};
	for (var i = 0; i < files.rows.length; i++) {
		var file = files.rows[i];
		if (file.value && file.value.binary) {
			var binaryId = file.value.binary.file.id ;
			//console.log(binaryId);
			getBinaryId(couchClient, binaryId, function(binary){
				console.log(binary)
			})
		}
	}
});
var MongoClient, collections, config, constants, runQuery;

//MongoClient = require("mongodb").MongoClient;

config = require("./config");

constants = require("./constants");


exports.connect = connect = function(collection, query) {
  return poolConnect(function(err, db) {
    var mongoCollection;
    mongoCollection = db!= null ? db.collection(collection) : void 0;
    return query(err,mongoCollection, function() {
      //return db.close();
    });
  });
}


exports.upsert=upsert=function(collection,iddoc,upsertdoc,callback) {
  return connect(collection, function(err, c, close) {	
    if(err) {
      return callback(constants.http.INTERNAL_ERROR,err);
    }
    return c.update(iddoc, upsertdoc,{upsert:true}, function(insertErr,docs) {
      close();
      if(!insertErr) {
        return callback(constants.http.CREATED, "yep");
      } else {
        return callback(constants.http.INTERNAL_ERROR, insertErr);
      }
    });
  });
};

exports.getCounters=getCounters=function(collection, querydoc, callback) {
  return connect(collection, function(err, c, close) {
    if(err) {
      return callback(constants.http.INTERNAL_ERROR, err);
    }
      return c.find(querydoc).toArray(function(queryErr, docs) {
        close();
	if(!queryErr) {
	//	console.log("getCounters");
	//	console.log(docs);
		return callback(constants.http.OK, docs);
	} else {
		return callback(constants.http.INTERNAL_ERROR, queryErr);
	}
      });	

  });
}

function getRandomColor() {
    var letters = '0123456789ABCDEF'.split('');
    var color = '#';
    for (var i = 0; i < 6; i++ ) {
        color += letters[Math.floor(Math.random() * 16)];
    }
    return color;
}

var topSlice = function() {
  var currentdate = moment.utc();
  var reportdate = currentdate;
  reportdate.minute(0);
  reportdate.second(0);
  return timeSlice(reportdate);

}
var timeSlice = function(mom) {
  var basedate =  moment.utc(new Date(2010, 1, 1));
  var currentdate = mom;
  var seconds = currentdate.diff(basedate,'seconds');
  return Math.floor(seconds/5)*5;
}

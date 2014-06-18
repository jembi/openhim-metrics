var metrics, IncrementCounter;
mongo = require("./mongo");
metrics = require('metrics');
config = require("./config");
constants = require("./constants");
moment = require("moment");
numbers = require("numbers");
var metricsServer = new metrics.Server(9092);
counter1 = new metrics.Counter;
metricsServer.addMetric('c.counter1', counter1);

var incrementCounter = function(params, callback) {
  iddoc = {_id : timeSlice(moment.utc())};
  upsertdoc = {$set: {l: "lalala"}, $inc: {c : 1,"a.c" : 1}};
  return mongo.upsert(params.c, iddoc,upsertdoc, callback);
};

var getData = function(params,callback) {
  console.log("getData - instrumentation");
  querydoc = {_id:  {$gt: startTime()}};
  console.log(querydoc);
  return mongo.getData(params.c, querydoc, callback);
};

var getCounters = function(params,callback) {
  
  console.log("getData - instrumentation");
  querydoc = {_id:  {$gt: startTime()}};
  console.log(querydoc);
  return mongo.getCounters(params.c, querydoc, function(status, returnValue) {
    if(status==constants.http.OK) {
      return callback(status, formatGraphData(returnValue));
    } else {
      return callback(status, returnValue);
    }
  } );
};

var updateMetrics = function(queryparams, body,  callback) {
  iddoc = {_id : timeSlice(moment.utc())};
  upsertdoc = {$set: {l: moment.utc().format("X")}, $inc: {c : 1}};
  for(var item in body.events) {
    var line = body.events[item];
    var avgkey = line.key+'.t';
    var countkey = line.key+'.c';
    upsertdoc["$inc"][avgkey] = line.avginc;
    upsertdoc["$inc"][countkey] = 1;
  }
  //console.log("*****************INSERT DOCUMENT*****************");
  //console.log(upsertdoc);
  return mongo.upsert('metrics5', iddoc,upsertdoc, callback);
};

var arrayToList = function(array) {
	var list = {};
	for(var i = 0; i< array.length; i++) {
		var key = array[i]["_id"];
		list[key] = array[i];
	}
	return list;
}
var timeFromSliceId = function(sliceid) {
var reportdate = moment.utc();
  reportdate.minute(0);
  reportdate.second(0);
  var date =  moment.utc(new Date(2010, 1, 1)).add('seconds', sliceid); 
  var seconds = date.diff(reportdate,'seconds'); 
 return (seconds+1)/5;

}
var formatGraphData = function(docs) {
	var vals = [];
	var seriesAvg = {};
	var seriesCnt = {};
        var seriesColours = {};
        var startSlice = startTime();	
 	var list = arrayToList(docs);
	for(var i = 0; i <720; i++) {
		var sliceid = startSlice+(i*5);
		if(list.hasOwnProperty(sliceid)) {
          		for (var key in list[sliceid]) {
            			if (key!="c"&&key!="l"&&key!="_id") {
              				if(!seriesAvg.hasOwnProperty(key)) {
               					seriesAvg[key]=[];
			                } 
			                var avgtime = list[sliceid][key].t/list[sliceid][key].c;
              				seriesAvg[key].push({x:timeFromSliceId(sliceid),y:avgtime});
					if(!seriesCnt.hasOwnProperty(key)) {
                                                seriesCnt[key]=[];
                                        }
                                        seriesCnt[key].push({x:timeFromSliceId(sliceid),y:list[sliceid][key].c});
			        }
	          	}
		}
		else {
			if(!seriesAvg.hasOwnProperty("ping")) {
                                                seriesAvg["ping"]=[];
                                        }
			seriesAvg["ping"].push({x:timeFromSliceId(sliceid),y:0});
			if(!seriesCnt.hasOwnProperty("ping")) {
                                                seriesCnt["ping"]=[];
                                        }
                        seriesCnt["ping"].push({x:timeFromSliceId(sliceid),y:0});
		}
	}
        var retdoc = [];
	var retAvg = [];
	var retCnt = [];
        var cnt = 0;
        for (var key in seriesAvg) {
		if(!seriesColours.hasOwnProperty(key)) {
			seriesColours[key] = constants.colours[cnt];
		}
        	retAvg.push({values: seriesAvg[key], key: key, color: seriesColours[key]});
	        cnt++;   
	}
	for (var key in seriesCnt) {
                if(!seriesColours.hasOwnProperty(key)) {
                        seriesColours[key] = constants.colours[cnt];
                }
                retCnt.push({values: seriesCnt[key], key: key, color: seriesColours[key]});
                cnt++;
        }
	retdoc.push(retAvg);
	retdoc.push(retCnt);
        return retdoc;
}

function getRandomColor() {
    var letters = '0123456789ABCDEF'.split('');
    var color = '#';
    for (var i = 0; i < 6; i++ ) {
        color += letters[Math.floor(Math.random() * 16)];
    }
    return color;
}

var startTime = function() {
  var reportdate = moment.utc();
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

exports.incrementCounter = incrementCounter;
exports.getData = getData;
exports.updateMetrics = updateMetrics;
exports.getCounters = getCounters;

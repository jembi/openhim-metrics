var instrumentation,GET_Handler, POST_Handler, app, config, constants, express, expressWinston, resultHandler, server, winston;

express = require("express");

//metrics = require('metrics');

expressWinston = require("express-winston");

winston = require("winston");

config = require("./config");

constants = require("./constants");

instrumentation = require("./instrumentation");

resultHandler = function(res, next, status, result) {
  if (status === constants.http.INTERNAL_ERROR) {
    return next(result);
  } else if (result) {
    return res.json(status, result);
  } else {
    return res.send(status);
  }
};

GET_Handler = function(handler) {

  config.getLogger().info("GET"); 
  return function(req, res, next) {
    console.log(req.query);
    return handler(req.query, function(status, result) {
      return resultHandler(res, next, status, result);
    });
  };
};

POST_Handler = function(handler) {

  return function(req, res, next) {
    return handler(req.query, req.body, function(status, result) {
      return resultHandler(res, next, status, result);
    });
  };
};

config.load();

app = express();
var allowCrossDomain = function(req, res, next) {
    res.header('Access-Control-Allow-Origin', "*");
    res.header('Access-Control-Allow-Methods', 'GET,PUT,POST,DELETE');
    res.header('Access-Control-Allow-Headers', 'Content-Type');

    next();
}
app.use(express.json());
app.use(allowCrossDomain);
app.use(expressWinston.logger({
  transports: [config.getLogger()]
}));

app.post("/instrumentation/updateMetrics", POST_Handler(instrumentation.updateMetrics));
app.get("/instrumentation/incrementCounter", GET_Handler(instrumentation.incrementCounter));
app.get("/instrumentation/getData", GET_Handler(instrumentation.getData));
app.get("/instrumentation/getCounters", GET_Handler(instrumentation.getCounters));
app.use(expressWinston.errorLogger({
  transports: config.loggerTransports()
}));

app.use(function(err, req, res, next) {
  return res.send(constants.http.INTERNAL_ERROR);
});

server = app.listen(process.env.PORT || constants.server.DEFAULT_PORT, function() {
  config.getLogger().info("Metrics service running on port " + (server.address().port));
  return config.getLogger().info("Environment: " + process.env.NODE_ENV);
});

exports.app = app;

fs = require "fs"
path = require "path"
winston = require "winston"


conf = {}

load = () ->
  file = switch process.env.NODE_ENV
    when "development" then "dev.json"
    when "preproduction" then "preprod.json"
    else "prod.json"
  conf = JSON.parse fs.readFileSync path.resolve "conf", file


loggerTransports = () ->
  if process.env.NODE_ENV is "development"
    [
      new winston.transports.Console
        colorize: true
    ]
  else
    [
      new winston.transports.Console
        colorize: true
      new winston.transports.DailyRotateFile
        filename: path.resolve "logs", "./drug-stock.log"
    ]

logger = new winston.Logger
  transports: loggerTransports()


exports.getConf = () -> conf
exports.getLogger = () -> logger
exports.loggerTransports = loggerTransports
exports.load = load

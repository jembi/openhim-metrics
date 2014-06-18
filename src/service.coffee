express = require "express"
expressWinston = require "express-winston"
winston = require "winston"
config = require "./config"
pharmacies = require "./pharmacies"
drugs = require "./drugs"
constants = require "./constants"


resultHandler = (res, next, status, result) ->
  if status is constants.http.INTERNAL_ERROR
    next result
  else if result
    res.json status, result
  else
    res.send status

GET_Handler = (handler) -> (req, res, next) ->
  handler req.params, (status, result) -> resultHandler(res, next, status, result)

POST_Handler = (handler) -> (req, res, next) ->
  handler req.params, req.body, (status, result) -> resultHandler(res, next, status, result)


# Load configuration
config.load()

# Setup express
app = express()
app.use express.json()

app.use expressWinston.logger
  transports: [ config.getLogger() ]


# Setup API paths
# The HIM Core will setup the base path (drugstock/v1/)
app.get "/pharmacies/:id", GET_Handler pharmacies.getPharmacy
app.get "/pharmacies", GET_Handler pharmacies.listAllPharmacyIdentifiers
app.post "/pharmacies", POST_Handler pharmacies.savePharmacy
app.put "/pharmacies/:id", POST_Handler pharmacies.updatePharmacy
app.get "/pharmacies/:id/current", GET_Handler pharmacies.getCurrentStockLevels
app.get "/pharmacies/:id/activation", GET_Handler pharmacies.getActivationRequest
app.post "/pharmacies/:id/activation", POST_Handler pharmacies.saveActivationRequest
app.get "/pharmacies/:id/dispensed/:date", GET_Handler pharmacies.getDispensedDocument
app.post "/pharmacies/:id/dispensed/:date", POST_Handler pharmacies.saveDispensedDocument
app.put "/pharmacies/:id/dispensed/:date", POST_Handler pharmacies.updateDispensedDocument
app.get "/pharmacies/:id/stocktakes/:date", GET_Handler pharmacies.getStockTakeDocument
app.post "/pharmacies/:id/stocktakes/:date", POST_Handler pharmacies.saveStockTakeDocument
app.put "/pharmacies/:id/stocktakes/:date", POST_Handler pharmacies.updateStockTakeDocument
app.get "/pharmacies/:id/stockarrivals/:date", GET_Handler pharmacies.getStockArrivalDocument
app.post "/pharmacies/:id/stockarrivals/:date", POST_Handler pharmacies.saveStockArrivalDocument
app.put "/pharmacies/:id/stockarrivals/:date", POST_Handler pharmacies.updateStockArrivalDocument

app.get "/drugs/:drugCodeType/:drugCode", GET_Handler drugs.getDrug
app.get "/drugs", GET_Handler drugs.listAllDrugIdentifiers
app.post "/drugs", POST_Handler drugs.saveDrug
app.put "/drugs/:drugCodeType/:drugCode", POST_Handler drugs.updateDrug

# Error handlers
app.use expressWinston.errorLogger
  transports: config.loggerTransports()

app.use (err, req, res, next) ->
  res.send constants.http.INTERNAL_ERROR

server = app.listen process.env.PORT or constants.server.DEFAULT_PORT, () ->
  config.getLogger().info "Drug stock service running on port #{server.address().port}"
  config.getLogger().info "Environment: #{process.env.NODE_ENV}"

exports.app = app

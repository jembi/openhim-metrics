MongoClient = require("mongodb").MongoClient
config = require "./config"
constants = require "./constants"

exports.runQuery = runQuery = (collection, query) ->
  conf = config.getConf().mongodb
  MongoClient.connect "mongodb://#{conf.host}:#{conf.port}/#{conf.db}", (err, db) ->
    mongoCollection = db?.collection collection
    index = indexForCollection collection if mongoCollection?
    if index
      mongoCollection.ensureIndex index, (err, indexName) ->
        query err, mongoCollection, () -> db.close()
    else
      query err, mongoCollection, () -> db.close()

indexForCollection = (collectionName) ->
  switch collectionName
    when collections.pharmacies then pharmacyId: 1
    when collections.drugs then "identifiers.drugCode": 1
    when collections.currentStockLevels then pharmacyId: 1
    when collections.activations then pharmacyId: 1
    when collections.dispensed then pharmacyId: 1, date: -1
    when collections.stockTake then pharmacyId: 1, date: -1
    when collections.stockArrivals then pharmacyId: 1, date: -1
    when collections.alerts then pharmacyId: 1, alertDate: -1
    else null

exports.saveDocument = (collection, doc, callback) ->
  runQuery collection, (err, c, close) ->
    return callback constants.http.INTERNAL_ERROR, err if err

    c.insert doc, (insertErr, docs) ->
      close()
      if not insertErr
        config.getLogger().info "Saved #{collection} document #{docs?[0]._id}"
        callback constants.http.CREATED, id: docs?[0]._id
      else
        callback constants.http.INTERNAL_ERROR, insertErr

exports.getDocument = (pharmacyId, collection, criteria, callback) ->
  config.getLogger().info "Querying for #{collection} document for pharmacy #{pharmacyId}"
  runQuery collection, (err, c, close) ->
    return callback constants.http.INTERNAL_ERROR, err if err

    c.findOne criteria, (findErr, result) ->
      close()
      if findErr
        callback constants.http.INTERNAL_ERROR, findErr
      else if result
        config.getLogger().info "Found #{collection} document #{result._id}"
        callback constants.http.OK, result
      else
        config.getLogger().info "Document for pharmacy #{pharmacyId} in #{collection} not found"
        callback constants.http.NOT_FOUND, null


exports.collections = collections =
  drugs: "drugs"
  pharmacies: "pharmacies"
  currentStockLevels: "currentStockLevels"
  activations: "activations"
  dispensed: "dispensed"
  stockTakes: "stockTakes"
  stockArrivals: "stockArrivals"
  alerts: "alerts"
  settings: "settings"

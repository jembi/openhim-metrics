moment = require "moment"
fs = require "fs"
constants = require "./constants"
config = require "./config"
mongo = require "./mongo"
drugs = require "./drugs"
orders = require "./orders"
alerts = require "./alerts"


# Pharmacies

getPharmacy = (params, callback) ->
  mongo.getDocument params.id, mongo.collections.pharmacies, pharmacyId: params.id, callback

listAllPharmacyIdentifiers = (params, callback) ->
  mongo.runQuery mongo.collections.pharmacies, (err, c, close) ->
    return callback constants.http.INTERNAL_ERROR, err if err
    cursor = c.find {}, { pharmacyId: 1 }
    cursor.toArray (err, identifiers) ->
      close()
      if err
       callback constants.http.INTERNAL_ERROR, err
      else
       callback constants.http.OK, pharmacies: identifiers

savePharmacy = (params, doc, callback) ->
  return callback constants.BAD_REQUEST, error: "pharmacyId not specified" if not doc.pharmacyId

  getPharmacy id: doc.pharmacyId, (status, result) ->
    if status is constants.http.OK
      callback constants.http.CONFLICT, result
    else if status is constants.http.NOT_FOUND
      doc.active = false
      mongo.saveDocument mongo.collections.pharmacies, doc, callback
    else
      callback status, result

setPharmacyActiveStatus = (pharmacyId, status, callback) ->
  mongo.runQuery mongo.collections.pharmacies, (err, c, close) ->
    return callback err if err

    c.update { pharmacyId: pharmacyId }, { $set: { active: status } }, (updateErr) ->
      close()
      callback updateErr ? null

updatePharmacy = (params, doc, callback) ->
  return callback constants.http.BAD_REQUEST, error: "Cannot update pharmacy id" if doc.pharmacyId

  getPharmacy params, (status, result) ->
    return callback status, result if status isnt constants.http.OK

    mongo.runQuery mongo.collections.pharmacies, (err, c, close) ->
      if err
        callback constants.http.INTERNAL_ERROR, updateErr
      else
        c.update { pharmacyId: params.id }, { $set: doc }, (updateErr) ->
          close()
          if not updateErr
            callback constants.http.OK, null
          else
            callback constants.http.INTERNAL_ERROR, updateErr


# Current Stock Levels

getCurrentStockLevels = (params, callback) ->
  mongo.getDocument params.id, mongo.collections.currentStockLevels, pharmacyId: params.id, (status, result) ->
    return callback constants.http.INTERNAL_ERROR, result if status isnt constants.http.OK
    drugs.denormalize result.stockLevels, (err) ->
      return callback constants.http.INTERNAL_ERROR, err if err
      callback status, result

updateStockLevels = (pharmacyId, date, stockLevels, stockLevelsChangeOp, callback) ->
  config.getLogger().info "Updating current stock levels document for pharmacy #{pharmacyId}"

  getStockLevels pharmacyId, (err, result) ->
    return callback err if err

    updateCall = (err, doc) ->
      return callback err if err
      updateStockLevelsDoc doc, date, stockLevels, stockLevelsChangeOp, callback
      config.getLogger().info "Updated current stock levels document for pharmacy #{pharmacyId}"

    if result
      updateCall null, result
    else
      insertNewStockLevelsDoc pharmacyId, updateCall

updateStockLevelsDoc = (doc, date, stockLevels, stockLevelsChangeOp, callback) ->
  for quantity in stockLevels
    processed = false

    for currentLevel in doc.stockLevels
      if currentLevel.drugId.equals(quantity.drugId)
        if canUpdate currentLevel.lastUpdate, date
          currentLevel.level = stockLevelsChangeOp currentLevel, quantity
          currentLevel.lastUpdate = date
        processed = true

    if not processed
      doc.stockLevels.push
        drugId: quantity.drugId,
        level: stockLevelsChangeOp(level: 0, quantity),
        triggerLevel: -1,
        avgDailyDispensed: -1,
        lastUpdate: date
  
  mongo.runQuery mongo.collections.currentStockLevels, (err, c, close) ->
    return callback err if err
    c.update { pharmacyId: doc.pharmacyId },{ $set: { stockLevels: doc.stockLevels } }, (err) ->
      close()
      callback err

canUpdate = (lastUpdateDate, docDate) ->
  not lastUpdateDate? or lastUpdateDate is docDate or moment(lastUpdateDate, "YYYYMMDD").isBefore moment(docDate, "YYYYMMDD")

insertNewStockLevelsDoc = (pharmacyId, callback) ->
  drugs.getAllDrugs (err, allDrugs) ->
    return callback err, null if err

    currentStockLevels =
      pharmacyId: pharmacyId,
      stockLevels: (
        {
          drugId: drug._id,
          level: 0,
          triggerLevel: -1,
          avgDailyDispensed: -1,
          lastUpdate: null
        } for drug in allDrugs
      )
    mongoInsertNewStockLevelsDoc currentStockLevels, (err, result) ->
      callback err, result

mongoInsertNewStockLevelsDoc = (doc, callback) ->
  mongo.runQuery mongo.collections.currentStockLevels, (err, c, close) ->
    return callback err, null if err
    c.insert doc, (err, docs) ->
      close()
      return callback err, null if err
      config.getLogger().info "Inserted new current stock levels document for pharmacy #{doc._id}"
      callback null, docs[0]


getStockLevels = (pharmacyId, callback) ->
  config.getLogger().info "Querying current stock levels for pharmacy #{pharmacyId}"
  mongo.runQuery mongo.collections.currentStockLevels, (err, c, close) ->
    return callback err, null if err
    c.findOne pharmacyId: pharmacyId, (err, result) ->
      close()
      if err
        callback err, null
      else if result
        config.getLogger().info "Current stock levels document exists for #{pharmacyId}"
        callback null, result
      else
        config.getLogger().info "No current stock levels document found for #{pharmacyId}"
        callback null, null


# Activation Requests

getActivationRequest = (params, callback) ->
  mongo.getDocument params.id, mongo.collections.activations, pharmacyId: params.id, callback

saveActivationRequest = (params, doc, callback) ->
  config.getLogger().info "Saving activation request for pharmacy #{params.id}"
  if not doc.leadTime
    callback constants.http.BAD_REQUEST, error: "leadTime not found"
  else if not doc.stockLevels
    callback constants.http.BAD_REQUEST, error: "stockLevels array not found"
  else
    getPharmacy params, (status, result) ->
      return callback status, result if status isnt constants.http.OK
      doc.pharmacyId = params.id
      setPharmacyActiveStatus params.id, true, (err) ->
        if err
          callback constants.http.INTERNAL_ERROR, err
        else
          saveActivationDoc params.id, doc, callback

saveActivationDoc = (pharmacyId, doc, callback) ->
  mongo.saveDocument mongo.collections.activations, doc, (status, result) ->
    drugs.normalize doc.stockLevels, false, (err, missingMappings) ->
      if err
        callback constants.http.INTERNAL_ERROR, err
      else if missingMappings
        callback constants.http.BAD_REQUEST, missingMappings: missingMappings
      else
        setOp = (old, value) -> value.level
        updateStockLevels pharmacyId, moment().format("YYYYMMDD"), doc.stockLevels, setOp, (err) ->
          if err
            callback constants.http.INTERNAL_ERROR, err
          else
            callback status, null


# Dispensed

getDispensedDocument = (params, callback) ->
  mongo.getDocument params.id, mongo.collections.dispensed, pharmacyId: params.id, date: params.date, callback

saveDispensedDocument = (params, doc, callback) ->
  processDispensedDocument saveStockDocumentHandler, params, doc, callback

updateDispensedDocument = (params, doc, callback) ->
  processDispensedDocument updateDispensedDocumentHandler, params, doc, callback

processDispensedDocument = (handler, params, doc, callback) ->
  return callback constants.http.BAD_REQUEST, error: "dispensed array not found" if not doc.dispensed

  handler mongo.collections.dispensed, params, doc, doc.dispensed,
    (old, value) -> old.level - value.quantity,
    (status, result) ->
      callback status, result
      processAlertTriggers params.id, params.date if status is constants.http.CREATED or status is constants.http.OK

updateDispensedDocumentHandler = (collection, params, doc, stock, updateStockLevelsOp, callback) ->
  config.getLogger().info "Updating #{collection} request for pharmacy #{params.id}"
  processStockDocument collection, params, doc, stock, updateStockLevelsOp, callback, checkForExistingEntry, (entryCheckerResult, mongoCallback) ->
    mongo.runQuery collection, (err, c, close) ->
      return mongoCallback constants.http.INTERNAL_ERROR, err if err
      for drug in stock
        processed = false
        for dbDrug in entryCheckerResult.dispensed
          if dbDrug.drugCode is drug.drugCode and dbDrug.drugCodeType is drug.drugCodeType
            dbDrug.quantity = dbDrug.quantity + drug.quantity
            processed = true
        if not processed
          entryCheckerResult.dispensed.push drug
      c.update { pharmacyId: params.id, date: params.date }, { $set: { dispensed: entryCheckerResult.dispensed, updated: moment().toDate() } }, (err) ->
        close()
        if err
          mongoCallback constants.http.INTERNAL_ERROR, error: err
        else
          mongoCallback constants.http.OK, null

# Alerts

processAlertTriggers = (pharmacyId, date) ->
  config.getLogger().info "Processing alert triggers for pharmacy #{pharmacyId}"
  mongo.runQuery mongo.collections.pharmacies, (err, c, close) ->
    c.findOne { pharmacyId: pharmacyId }, { active: 1, leadTime: 1 }, (err, result) ->
      close()
      if result?.active
        updateTriggerLevels pharmacyId, result.leadTime ? 5, (err) ->
          config.getLogger().info "Generating alerts for pharmacy #{pharmacyId}"
          lowDrugs = []
          generateAlerts pharmacyId, lowDrugs, (err) ->
            if not err
              config.getLogger().info "Finished generating alerts for pharmacy #{pharmacyId}"
              # just save to tmp dir for now
              now = moment().format "YYYYMMDD-HHmm"
              orders.generateOrderNotification fs.createWriteStream("/tmp/#{pharmacyId}-#{now}.pdf"), pharmacyId, date, lowDrugs, (err) ->
                config.getLogger().info "Generated order notification"
            else
              config.getLogger().error err
      else
        config.getLogger().info "Pharmacy is inactive. Skipping alert processing."


buildAvgDailyDispensedQueryPipeline = (pharmacyId, earliestDispensedDate) ->
  [
    { $match:
      pharmacyId: pharmacyId
      _date:
        $gte: earliestDispensedDate.toDate() }
    { $unwind: "$dispensed" }
    { $group:
      _id:
        drugCode: "$dispensed.drugCode"
        drugCodeType: "$dispensed.drugCodeType"
      avgDailyDispensed:
        $avg: "$dispensed.quantity" }
    { $project:
      drugCode: "$_id.drugCode"
      drugCodeType: "$_id.drugCodeType"
      avgDailyDispensed: 1 }
  ]

updateTriggerLevels = (pharmacyId, leadTime, callback) ->
  config.getLogger().info "Calculating Avg Daily Dispensed amounts and updating stock trigger levels for pharmacy #{pharmacyId}"
  earliestDispensedDate = moment().subtract "days", config.getConf().dispensedHistoryDays ? 90
  mongo.runQuery mongo.collections.dispensed, (err, c, close) ->
    c.aggregate buildAvgDailyDispensedQueryPipeline(pharmacyId, earliestDispensedDate), (err, result) ->
      close()
      updateTriggerLevelsDoc pharmacyId, leadTime, result, (err) ->
        callback err

updateTriggerLevelsDoc = (pharmacyId, leadTime, avgDailyDispensed, callback) ->
  drugs.normalize avgDailyDispensed, true, (err, missingMappings) ->
    mongo.runQuery mongo.collections.currentStockLevels, (err, c, close) ->
      bufferTime = config.getConf().drugSafetyWindowDays
      alertTime = config.getConf().drugAlertWindowDays

      # keep track of the update queries
      reportBack = (false for [0...avgDailyDispensed.length])

      queryId = 0
      for avgDD in avgDailyDispensed
        do (avgDD, queryId) ->
          newTriggerLevel = (avgDD.avgDailyDispensed * (leadTime + bufferTime + alertTime) + (avgDD.minimumStockLevel ? 0))
          c.update { pharmacyId: pharmacyId, "stockLevels.drugId": avgDD.drugId },
            { $set: {
                "stockLevels.$.triggerLevel": newTriggerLevel
                "stockLevels.$.avgDailyDispensed": avgDD.avgDailyDispensed
              }
            }, (err) ->
              throw err if err
              reportBack[queryId] = true
              # have all queries reported back yet?
              done = reportBack.reduce (t, s) -> t and s
              if done
                close()
                config.getLogger().info "Updated stock trigger levels for pharmacy #{pharmacyId}"
                callback null

        queryId++


generateAlerts = (pharmacyId, lowDrugsDst, callback) ->
  mongo.getDocument pharmacyId, mongo.collections.currentStockLevels, pharmacyId: pharmacyId, (status, result) ->
    return callback "Failed to load currentStockLevels document for pharmacy #{pharmacyId}" if status isnt constants.http.OK

    for stockLevel in result.stockLevels
      if stockLevel.triggerLevel >= 0 <= stockLevel.level <= stockLevel.triggerLevel
        config.getLogger().info "Pharmacy #{pharmacyId}: Stock low for drug #{stockLevel.drugId}"
        lowDrugsDst.push drugId: stockLevel.drugId, level: stockLevel.level, avgDailyDispensed: stockLevel.avgDailyDispensed

    drugs.denormalize lowDrugsDst, (err) ->
      callback err

      now = moment()
      for drug in lowDrugsDst
        alerts.sendAlert { pharmacyId: pharmacyId, barcode: drug.barcode }, (err) ->
          config.getLogger().error err if err
          mongo.saveDocument mongo.collections.alerts,
            pharmacyId: pharmacyId
            drugId: stockLevel.drugId
            stockLevel: stockLevel.level
            triggerLevel: stockLevel.triggerLevel
            avgDailyDispensed: stockLevel.avgDailyDispensed
            alertDate: now.format("YYYYMMDD")
            alertType: "Stock Low"
            sent: (err==null)
            dateSent: (if err==null then now.toDate() else null)
            sentTo: "HIM",
            (status, result) -> config.getLogger().error result if status is constants.http.INTERNAL_ERROR


# Stock Takes

getStockTakeDocument = (params, callback) ->
  mongo.getDocument params.id, mongo.collections.stockTakes, pharmacyId: params.id, date: params.date, callback

saveStockTakeDocument = (params, doc, callback) ->
  processStockTakeDocument saveStockDocumentHandler, params, doc, callback

updateStockTakeDocument = (params, doc, callback) ->
  processStockTakeDocument updateStockTakeDocumentHandler, params, doc, callback

processStockTakeDocument = (handler, params, doc, callback) ->
  return callback constants.http.BAD_REQUEST, error: "stockLevels array not found" if not doc.stockLevels
  
  handler mongo.collections.stockTakes, params, doc, doc.stockLevels,
    (old, value) -> value.level,
    callback

updateStockTakeDocumentHandler = (collection, params, doc, stock, updateStockLevelsOp, callback) ->
  config.getLogger().info "Updating #{collection} request for pharmacy #{params.id}"
  processStockDocument collection, params, doc, stock, updateStockLevelsOp, callback, checkForExistingEntry, (entryCheckerResult, mongoCallback) ->
    mongo.runQuery collection, (err, c, close) ->
      return mongoCallback constants.http.INTERNAL_ERROR, err if err
      for drug in stock
        processed = false
        for dbDrug in entryCheckerResult.stockLevels
          if dbDrug.drugCode is drug.drugCode and dbDrug.drugCodeType is drug.drugCodeType
            dbDrug.level = drug.level
            processed = true
        if not processed
          entryCheckerResult.stockLevels.push drug
      c.update { pharmacyId: params.id, date: params.date }, { $set: { stockLevels: entryCheckerResult.stockLevels, updated: moment().toDate() } }, (err) ->
        close()
        if err
          mongoCallback constants.http.INTERNAL_ERROR, error: err
        else
          mongoCallback constants.http.OK, null


# Stock Arrivals

getStockArrivalDocument = (params, callback) ->
  mongo.getDocument params.id, mongo.collections.stockArrivals, pharmacyId: params.id, date: params.date, callback

saveStockArrivalDocument = (params, doc, callback) ->
  processStockArrivalDocument saveStockDocumentHandler, params, doc, callback

updateStockArrivalDocument = (params, doc, callback) ->
  processStockArrivalDocument updateStockArrivalDocumentHandler, params, doc, callback

processStockArrivalDocument = (handler, params, doc, callback) ->
  callback constants.http.BAD_REQUEST, error: "stockArrived array not found" if not doc.stockArrived
  
  handler mongo.collections.stockArrivals, params, doc, doc.stockArrived,
    (old, value) -> old.level + value.quantity,
    callback

updateStockArrivalDocumentHandler = (collection, params, doc, stock, updateStockLevelsOp, callback) ->
  config.getLogger().info "Updating #{collection} request for pharmacy #{params.id}"
  processStockDocument collection, params, doc, stock, updateStockLevelsOp, callback, checkForExistingEntry, (entryCheckerResult, mongoCallback) ->
    mongo.runQuery collection, (err, c, close) ->
      return mongoCallback constants.http.INTERNAL_ERROR, err if err
      for drug in stock
        processed = false
        for dbDrug in entryCheckerResult.stockArrived
          if dbDrug.drugCode is drug.drugCode and dbDrug.drugCodeType is drug.drugCodeType
            dbDrug.quantity = dbDrug.quantity + drug.quantity
            processed = true
        if not processed
          entryCheckerResult.stockArrived.push drug
      c.update { pharmacyId: params.id, date: params.date }, { $set: { stockArrived: entryCheckerResult.stockArrived, updated: moment().toDate() } }, (err) ->
        close()
        if err
          mongoCallback constants.http.INTERNAL_ERROR, error: err
        else
          mongoCallback constants.http.OK, null

# General

saveStockDocumentHandler = (collection, params, doc, stock, updateStockLevelsOp, callback) ->
  config.getLogger().info "Saving #{collection} request for pharmacy #{params.id}"
  doc._date = moment(params.date, "YYYYMMDD").toDate()
  doc.created = moment().toDate()
  doc.updated = null
  processStockDocument collection, params, doc, stock, updateStockLevelsOp, callback, conflictOnExistingEntry, (entryCheckerResult, mongoCallback) ->
    mongo.saveDocument collection, doc, mongoCallback


processStockDocument = (collection, params, doc, stock, updateStockLevelsOp, callback, existingEntryChecker, mongoQuery) ->
  getPharmacy params, (getPharmStatus, getPharmResult) ->
    return callback getPharmStatus, getPharmResult if getPharmStatus isnt constants.http.OK

    doc.pharmacyId = params.id
    doc.date = params.date

    validateDate params.date, (dateErr) ->
      return callback constants.http.BAD_REQUEST, dateErr if dateErr
      existingEntryChecker collection, params, (validateStatus, validateResult) ->
        return callback validateStatus, validateResult if validateStatus isnt constants.http.OK
        drugs.normalize stock, false, (err, missingMappings) ->
          if err
            callback constants.http.INTERNAL_ERROR, err
          else if missingMappings
            callback constants.http.BAD_REQUEST, missingMappings: missingMappings
          else
            mongoQuery validateResult, (status, result) ->
              return callback status, result if status isnt constants.http.OK and status isnt constants.http.CREATED
              updateStockLevels params.id, params.date, stock, updateStockLevelsOp, (err) ->
                if err
                  callback constants.http.INTERNAL_ERROR, err
                else
                  callback status, null


validateDate = (date, callback) ->
  date = moment(date, "YYYYMMDD").startOf "day"
  today = moment().startOf "day"

  if !date.isValid()
    callback error: "#{date} has an invalid date format. Expected yyyyMMdd"
  else if date.isAfter today
    callback error: "#{date} is in the future"
  else if not config.getConf().enableBackentry and date.isBefore today
    callback error: "#{date} is in the past"
  else
    callback null

conflictOnExistingEntry = (collection, params, callback) ->
  mongo.getDocument params.id, collection, pharmacyId: params.id, date: params.date, (status, result) ->
    if status is constants.http.OK
      config.getLogger().info "Conflict: #{collection} document for date #{params.date} already exists"
      callback constants.http.CONFLICT, result
    else
      callback constants.http.OK, null

checkForExistingEntry = (collection, params, callback) ->
  mongo.getDocument params.id, collection, pharmacyId: params.id, date: params.date, callback


exports.getPharmacy = getPharmacy
exports.listAllPharmacyIdentifiers = listAllPharmacyIdentifiers
exports.savePharmacy = savePharmacy
exports.updatePharmacy = updatePharmacy
exports.getCurrentStockLevels = getCurrentStockLevels
exports.getActivationRequest = getActivationRequest
exports.saveActivationRequest = saveActivationRequest
exports.getDispensedDocument = getDispensedDocument
exports.saveDispensedDocument = saveDispensedDocument
exports.updateDispensedDocument = updateDispensedDocument
exports.getStockTakeDocument = getStockTakeDocument
exports.saveStockTakeDocument = saveStockTakeDocument
exports.updateStockTakeDocument = updateStockTakeDocument
exports.getStockArrivalDocument = getStockArrivalDocument
exports.saveStockArrivalDocument = saveStockArrivalDocument
exports.updateStockArrivalDocument = updateStockArrivalDocument

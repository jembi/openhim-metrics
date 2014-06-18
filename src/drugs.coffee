mongo = require "./mongo"
constants = require "./constants"
config = require "./config"


getDrug = (params, callback) ->
  config.getLogger().info "Querying for drug #{params.drugCodeType}-#{params.drugCode}"
  mongo.runQuery mongo.collections.drugs, (err, c, close) ->
    return callback constants.http.INTERNAL_ERROR, err if err

    c.findOne
      identifiers:
        $elemMatch:
          drugCode: params.drugCode,
          drugCodeType: params.drugCodeType,
      (err, result) ->
        close()
        if err
          callback constants.http.INTERNAL_ERROR, err
        else if result
          config.getLogger().info "Drug found #{result.name}"
          callback constants.http.OK, result
        else
          config.getLogger().info "Drug #{params.drugCodeType}-#{params.drugCode} not found"
          callback constants.http.NOT_FOUND, null


getAllDrugs = (callback) -> findAllDrugs({ _id: 1 }, callback)

listAllDrugIdentifiers = (params, callback) ->
  findAllDrugs { _id: 1, identifiers: 1 }, (err, drugs) ->
    if err
      callback constants.http.INTERNAL_ERROR, err
    else
      callback constants.http.OK, drugs: drugs

findAllDrugs = (projection, callback) ->
  mongo.runQuery mongo.collections.drugs, (err, c, close) ->
    return callback err, null if err

    cursor = c.find {}, projection
    cursor.toArray (err, drugs) ->
      close()
      callback err, drugs


saveDrug = (params, doc, callback) ->
  return callback constants.http.BAD_REQUEST, error: "identifiers not found" if not doc.identifiers
  return callback constants.http.BAD_REQUEST, error: "barcode not found" if not doc.barcode

  # TODO check for duplicates more efficiently
  findAllDrugs { identifiers: 1 }, (err, drugs) ->
    return callback constants.http.INTERNAL_ERROR, err if err

    for drug in drugs
      for id in drug.identifiers
        for docId in doc.identifiers
          if id.drugCode is docId.drugCode and id.drugCodeType is docId.drugCodeType
            return callback constants.http.CONFLICT, drug

    mongo.runQuery mongo.collections.drugs, (err, c, close) ->
      return callback constants.http.INTERNAL_ERROR, err if err

      c.insert doc, (err, docs) ->
        close()
        if err
          callback constants.http.INTERNAL_ERROR, err
        else
          config.getLogger().info "Inserted drug #{docs?[0]._id}"
          callback constants.http.CREATED, null


updateDrug = (params, doc, callback) ->
  return callback constants.http.BAD_REQUEST, error: "Updating of drug identifiers is not supported" if doc.identifiers

  getDrug params, (status, result) ->
    return callback status, result if status isnt constants.http.OK

    mongo.runQuery mongo.collections.drugs, (err, c, close) ->
      return callback constants.http.INTERNAL_ERROR, err if err

      c.update {
        identifiers:
          $elemMatch:
            drugCode: params.drugCode,
            drugCodeType: params.drugCodeType
        }, { $set: doc }, (err) ->
          close()
          if not err
            callback constants.http.OK, null
          else
            callback constants.http.INTERNAL_ERROR, err


# Map drugs to internal _ids
normalize = (drugs, projectDrugInfo, callback) ->
  config.getLogger().info "Mapping drugs to internal identifiers"
  mongo.runQuery mongo.collections.drugs, (err, c, close) ->
    project = $project:
      _id: 1
      drugCode: "$identifiers.drugCode"
      drugCodeType: "$identifiers.drugCodeType"
    if projectDrugInfo
      project.$project.minimumStockLevel = 1

    pipeline = [
      { $match:
        identifiers:
          $elemMatch:
            drugCode:
              $in: (d.drugCode for d in drugs)
      },
      { $unwind: "$identifiers" }
      project
    ]
    c.aggregate pipeline, (err, result) ->
      close()
      return callback err, null if err

      for res in result
        drugs.map (drug) ->
          if drug.drugCodeType is res.drugCodeType and drug.drugCode is res.drugCode
            drug.drugId = res._id
            drug.minimumStockLevel = res.minimumStockLevel if projectDrugInfo

      callback null, getMissingMappings drugs

getMissingMappings = (drugs) ->
  missingMappings = []
  drugs.map (drug) -> missingMappings.push drugCode: drug.drugCode, drugCodeType: drug.drugCodeType if not drug.drugId
  return if missingMappings.length>0 then missingMappings else null


denormalize = (drugs, callback) ->
  mongo.runQuery mongo.collections.drugs, (err, c, close) ->
    return callback err if err

    # keep track of the fetch queries
    reportBack = (false for [0...drugs.length])

    queryId = 0
    for drug in drugs
      do (drug, queryId) ->
          c.findOne _id: drug.drugId ? drug.id, (err, result) ->
            if not err
              drug.name = result?.name
              drug.barcode = result?.barcode
              drug.identifiers = result?.identifiers
            else
              config.getLogger().error err

            reportBack[queryId] = true
            # have all queries reported back yet?
            done = reportBack.reduce (t, s) -> t and s
            if done
              close()
              callback null

      queryId++


exports.getDrug = getDrug
exports.getAllDrugs = getAllDrugs
exports.listAllDrugIdentifiers = listAllDrugIdentifiers
exports.saveDrug = saveDrug
exports.updateDrug = updateDrug
exports.normalize = normalize
exports.denormalize = denormalize

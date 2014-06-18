# Integration Tests
#
# Integration testing is performed by setting up a test database in mongo.
# Each endpoint on the API is then tested and the database is dropped afterwards.
#
MongoClient = require("mongodb").MongoClient
request = require "supertest"
should = require "should"
moment = require "moment"
constants = require "../lib/constants"
config = require "../lib/config"
service = require "../lib/service"
drugs = require "../lib/drugs"
pharmacies = require "../lib/pharmacies"
mongo = require "../lib/mongo"

# Resources

testDrug1 = {
  name: "Test Drug"
  description: "This is a test drug"
  barcode: "1111"
  identifiers: [
    drugCode: "DRUG1"
    drugCodeType: "TEST"
  ]
  minimumStockLevel: 100
}

testDrug2 = {
  name: "Another Test Drug"
  description: "This is a another test drug"
  barcode: "2222"
  identifiers: [
    drugCode: "DRUG2"
    drugCodeType: "TEST"
  ]
  minimumStockLevel: 100
}

testDrug3 = {
  name: "A Third Test Drug"
  description: "This is a third test drug"
  barcode: "3333"
  identifiers: [
    drugCode: "DRUG3"
    drugCodeType: "TEST"
  ]
  minimumStockLevel: 50
}

drugUpdate = minimumStockLevel: 500

testPharm1 = {
  name: "Good Health Pharmacy"
  pharmacyId: "0000"
  leadTime: 5
}

testPharm2 = {
  name: "Another Pharmacy"
  pharmacyId: "0001"
  leadTime: 6
}

testPharm3 = {
  name: "A Third Pharmacy"
  pharmacyId: "0002"
  leadTime: 7
}

pharmUpdate = customField: "with custom data!"

baseStockLevel = 1000

baseActivation = {
  leadTime: 5,
  stockLevels: [
    {
      drugCode: "DRUG1"
      drugCodeType: "TEST"
      level: baseStockLevel
    },
    {
      drugCode: "DRUG2"
      drugCodeType: "TEST"
      level: baseStockLevel
    }
  ]
}

testActivation = {
  leadTime: 3,
  stockLevels: [
    {
      drugCode: "DRUG1"
      drugCodeType: "TEST"
      level: 2000
    },
    {
      drugCode: "DRUG2"
      drugCodeType: "TEST"
      level: 3000
    }
  ]
}

testDispensed = {
  dispensed: [
    {
      drugCode: "DRUG1"
      drugCodeType: "TEST"
      quantity: 40
    },
    {
      drugCode: "DRUG2"
      drugCodeType: "TEST"
      quantity: 60
    }
  ]
}

testStockTake = {
  stockLevels: [
    {
      drugCode: "DRUG1"
      drugCodeType: "TEST"
      level: 5000
    },
    {
      drugCode: "DRUG2"
      drugCodeType: "TEST"
      level: 5000
    }
  ]
}

testStockTakeUpdate = {
  stockLevels: [
    {
      drugCode: "DRUG2"
      drugCodeType: "TEST"
      level: 3000
    },
    {
      drugCode: "DRUG3"
      drugCodeType: "TEST"
      level: 3000
    }
  ]
}

expectedStockTakeAfterUpdate = {
  stockLevels: [
    {
      drugCode: "DRUG1"
      drugCodeType: "TEST"
      level: 5000
    },
    {
      drugCode: "DRUG2"
      drugCodeType: "TEST"
      level: 3000
    },
    {
      drugCode: "DRUG3"
      drugCodeType: "TEST"
      level: 3000
    }
  ]
}

testStockArrival = {
  stockArrived: [
    {
      drugCode: "DRUG1"
      drugCodeType: "TEST"
      quantity: 500
    },
    {
      drugCode: "DRUG2"
      drugCodeType: "TEST"
      quantity: 500
    }
  ]
}

testStockArrivalUpdate = {
  stockArrived: [
    {
      drugCode: "DRUG2"
      drugCodeType: "TEST"
      quantity: 100
    },
    {
      drugCode: "DRUG3"
      drugCodeType: "TEST"
      quantity: 100
    }
  ]
}

expectedStockArrivalAfterUpdate = {
  stockArrived: [
    {
      drugCode: "DRUG1"
      drugCodeType: "TEST"
      quantity: 500
    },
    {
      drugCode: "DRUG2"
      drugCodeType: "TEST"
      quantity: 600
    },
    {
      drugCode: "DRUG3"
      drugCodeType: "TEST"
      quantity: 100
    }
  ]
}

today = moment().format "YYYYMMDD"

# Setup

testDB = null

cleanup = (callback) ->
  conf = config.getConf().mongodb
  MongoClient.connect "mongodb://#{conf.host}:#{conf.port}/#{testDB}", (err, db) ->
    db.dropDatabase (err, result) ->
      db.close()
      callback()

saveResource = (method, resource, next) ->
  method null, resource, (status, result) ->
      if status isnt constants.http.CREATED
        cleanup () -> throw result
      else
        next()

saveDrug = (drug, next) -> saveResource drugs.saveDrug, drug, next
savePharm = (pharm, next) -> saveResource pharmacies.savePharmacy, pharm, next

clearCollection = (db, collection, next) -> db.collection(collection).remove {}, (err, num) -> next()

loadBaseActivation = (done) ->
  pharmacies.saveActivationRequest id: testPharm1.pharmacyId, baseActivation, (status, result) -> done()

# Support functions

testPOSTStockDocument = (url, doc, docStockLevels, drugLevelTest, done) ->
  request service.app
    .post url
    .send doc
    .expect constants.http.CREATED
    .end (err, res) ->
      return done err if err
      checkStockLevels testPharm1, docStockLevels, drugLevelTest, done

checkStockLevels = (testPharm, testStockLevels, drugLevelTest, callback) ->
  pharmacies.getCurrentStockLevels id: testPharm.pharmacyId, (status, result) ->
    drugs.denormalize result.stockLevels, (err) ->
      for drug in testStockLevels
        for dbDrug in result.stockLevels
          for id in dbDrug.identifiers
            if id.drugCode is drug.drugCode and id.drugCodeType is drug.drugCodeType
              drugLevelTest dbDrug, drug
      callback()

# Tests

describe "service", () ->
  before (done) ->
    testDB = "drugstock_integrationtest_#{moment().format('YYYYMMDDHHmmss')}"
    config.getConf().mongodb.db = testDB
    done()

  beforeEach (done) ->
    saveDrug testDrug1, () -> saveDrug testDrug2, () ->
      savePharm testPharm1, () -> savePharm testPharm2, () ->
        loadBaseActivation done

  after (done) -> cleanup () -> done()

  afterEach (done) ->
    conf = config.getConf().mongodb
    MongoClient.connect "mongodb://#{conf.host}:#{conf.port}/#{testDB}", (err, db) ->
      clearCollection db, mongo.collections.currentStockLevels, () ->
        clearCollection db, mongo.collections.activations, () ->
          clearCollection db, mongo.collections.dispensed, () ->
            clearCollection db, mongo.collections.stockTakes, () ->
              clearCollection db, mongo.collections.stockArrivals, () ->
                clearCollection db, mongo.collections.alerts, () ->
                  clearCollection db, mongo.collections.pharmacies, () ->
                    clearCollection db, mongo.collections.drugs, () ->
                      db.close()
                      done()

  # Pharmacies
  
  describe "GET /pharmacies/:id", () ->
    it "should return status OK if found", (done) ->
      request service.app
        .get "/pharmacies/#{testPharm1.pharmacyId}"
        .expect "Content-Type", /json/
        .expect /"name": "Good Health Pharmacy"/
        .expect constants.http.OK, done

    it "should return status NOT_FOUND if not found", (done) ->
      request service.app
        .get "/pharmacies/NOTTHERE"
        .expect constants.http.NOT_FOUND, done

  describe "POST /pharmacies", () ->
    it "should return status CREATED if created", (done) ->
      request service.app
        .post "/pharmacies"
        .send testPharm3
        .expect constants.http.CREATED
        .end (err, res) ->
          return done err if err
          pharmacies.getPharmacy id: testPharm3.pharmacyId, (status, result) ->
            status.should.equal constants.http.OK
            result.should.have.property "name", testPharm3.name
            done()

    it "should return status CONFLICT if pharmacy with matching id already exists", (done) ->
      request service.app
        .post "/pharmacies"
        .send testPharm1
        .expect constants.http.CONFLICT, done

  describe "PUT /pharmacies/:id", () ->
    it "should return status OK if updated", (done) ->
      request service.app
        .put "/pharmacies/#{testPharm1.pharmacyId}"
        .send pharmUpdate
        .expect constants.http.OK
        .end (err, res) ->
          return done err if err
          pharmacies.getPharmacy id: testPharm1.pharmacyId, (status, result) ->
            status.should.equal constants.http.OK
            result.should.have.property "name", testPharm1.name
            result.should.have.property "leadTime", testPharm1.leadTime
            result.should.have.property "customField", pharmUpdate.customField
            done()

    it "should return status NOT_FOUND if the pharmacy does not exist", (done) ->
      request service.app
        .put "/pharmacies/NOTTHERE"
        .send pharmUpdate
        .expect constants.http.NOT_FOUND, done

  # Activations

  describe "POST /pharmacies/:id/activations", () ->
    it "should return status CREATED if created and initialize stock levels", (done) ->
      request service.app
        .post "/pharmacies/#{testPharm2.pharmacyId}/activation"
        .send testActivation
        .expect constants.http.CREATED
        .end (err, res) ->
          return done err if err
          test = (dbLevel, drugLevel) -> dbLevel.level.should.equal drugLevel.level
          checkStockLevels testPharm2, testActivation.stockLevels, test, done

    it "should set the pharmacy's activated flag to true", (done) ->
      pharmacies.getPharmacy id: testPharm2.pharmacyId, (status, result) ->
        return done result if status is not constants.http.OK
        result.active.should.equal false
        request service.app
          .post "/pharmacies/#{testPharm2.pharmacyId}/activation"
          .send testActivation
          .expect constants.http.CREATED
          .end (err, res) ->
            return done err if err
            pharmacies.getPharmacy id: testPharm2.pharmacyId, (status, result) ->
              return done result if status is not constants.http.OK
              result.active.should.be.true
              done()

  # Dispensed
 
  describe "POST /pharmacies/:id/dispensed/:date", () ->
    # Triggers and alerts are processed asyncronously after responding, so cannot be integration tested as part from the service layer
 
    it "should return status NOT_FOUND if the pharmacy doesn't exist", (done) ->
      request service.app
        .post "/pharmacies/NOTTHERE/dispensed/#{today}"
        .send testDispensed
        .expect constants.http.NOT_FOUND, done

    it "should return status BAD_REQUEST if the date is in the future", (done) ->
      request service.app
        .post "/pharmacies/#{testPharm1.pharmacyId}/dispensed/#{moment().add('days', 1).format('YYYYMMDD')}"
        .send testDispensed
        .expect constants.http.BAD_REQUEST, done

    it "should return status BAD_REQUEST if the date malformed", (done) ->
      request service.app
        .post "/pharmacies/#{testPharm1.pharmacyId}/dispensed/BADDATE"
        .send testDispensed
        .expect constants.http.BAD_REQUEST, done

  # Stock Takes
 
  describe "POST /pharmacies/:id/stocktakes/:date", () ->
    it "should return status CREATED if created and update stock levels to absolute values", (done) ->
      url = "/pharmacies/#{testPharm1.pharmacyId}/stocktakes/#{today}"
      test = (dbLevel, drugLevel) -> dbLevel.level.should.equal drugLevel.level
      testPOSTStockDocument url, testStockTake, testStockTake.stockLevels, test, done

    it "should return status NOT_FOUND if the pharmacy doesn't exist", (done) ->
      request service.app
        .post "/pharmacies/NOTTHERE/stocktakes/#{today}"
        .send testStockTake
        .expect constants.http.NOT_FOUND, done

    it "should return status BAD_REQUEST if the date is in the future", (done) ->
      request service.app
        .post "/pharmacies/#{testPharm1.pharmacyId}/stocktakes/#{moment().add('days', 1).format('YYYYMMDD')}"
        .send testStockTake
        .expect constants.http.BAD_REQUEST, done

    it "should return status BAD_REQUEST if the date malformed", (done) ->
      request service.app
        .post "/pharmacies/#{testPharm1.pharmacyId}/stocktakes/BADDATE"
        .send testStockTake
        .expect constants.http.BAD_REQUEST, done

    it "should return status CONFLICT if a stock take was already done for a particular day", (done) ->
      pharmacies.saveStockTakeDocument { id: testPharm1.pharmacyId, date: today }, testStockTake, (status, result) ->
        status.should.equal constants.http.CREATED
        request service.app
          .post "/pharmacies/#{testPharm1.pharmacyId}/stocktakes/#{today}"
          .send testStockTake
          .expect constants.http.CONFLICT, done
 
  describe "PUT /pharmacies/:id/stocktakes/:date", () ->
    it "should return status OK if updated and update stock levels to absolute values", (done) ->
      saveDrug testDrug3, () ->
        pharmacies.saveStockTakeDocument { id: testPharm1.pharmacyId, date: today }, testStockTake, (status, result) ->
          status.should.equal constants.http.CREATED
          request service.app
            .put "/pharmacies/#{testPharm1.pharmacyId}/stocktakes/#{today}"
            .send testStockTakeUpdate
            .expect constants.http.OK
            .end (err, res) ->
              return done err if err
              test = (dbLevel, drugLevel) -> dbLevel.level.should.equal drugLevel.level
              checkStockLevels testPharm1, expectedStockTakeAfterUpdate, test, done

    it "should return status NOT_FOUND if the pharmacy doesn't exist", (done) ->
      request service.app
        .put "/pharmacies/NOTTHERE/stocktakes/#{today}"
        .send testStockTake
        .expect constants.http.NOT_FOUND, done

    it "should return status BAD_REQUEST if the date is in the future", (done) ->
      request service.app
        .put "/pharmacies/#{testPharm1.pharmacyId}/stocktakes/#{moment().add('days', 1).format('YYYYMMDD')}"
        .send testStockTake
        .expect constants.http.BAD_REQUEST, done

    it "should return status BAD_REQUEST if the date malformed", (done) ->
      request service.app
        .put "/pharmacies/#{testPharm1.pharmacyId}/stocktakes/BADDATE"
        .send testStockTake
        .expect constants.http.BAD_REQUEST, done

    it "should return status NOT_FOUND if no stock take exists for the particular date", (done) ->
      request service.app
        .put "/pharmacies/#{testPharm1.pharmacyId}/stocktakes/#{today}"
        .send testStockTake
        .expect constants.http.NOT_FOUND, done

  # Stock Arrivals
 
  describe "POST /pharmacies/:id/stockarrivals/:date", () ->
    it "should return status CREATED if created and increment stock levels", (done) ->
      url = "/pharmacies/#{testPharm1.pharmacyId}/stockarrivals/#{today}"
      test = (dbLevel, drugLevel) -> dbLevel.level.should.equal baseStockLevel + drugLevel.quantity
      testPOSTStockDocument url, testStockArrival, testStockArrival.stockArrived, test, done

    it "should return status NOT_FOUND if the pharmacy doesn't exist", (done) ->
      request service.app
        .post "/pharmacies/NOTTHERE/stockarrivals/#{today}"
        .send testStockArrival
        .expect constants.http.NOT_FOUND, done

    it "should return status BAD_REQUEST if the date is in the future", (done) ->
      request service.app
        .post "/pharmacies/#{testPharm1.pharmacyId}/stockarrivals/#{moment().add('days', 1).format('YYYYMMDD')}"
        .send testStockArrival
        .expect constants.http.BAD_REQUEST, done

    it "should return status BAD_REQUEST if the date malformed", (done) ->
      request service.app
        .post "/pharmacies/#{testPharm1.pharmacyId}/stockarrivals/BADDATE"
        .send testStockArrival
        .expect constants.http.BAD_REQUEST, done

    it "should return status CONFLICT if a stock arrival was already done for a particular day", (done) ->
      pharmacies.saveStockArrivalDocument { id: testPharm1.pharmacyId, date: today }, testStockArrival, (status, result) ->
        status.should.equal constants.http.CREATED
        request service.app
          .post "/pharmacies/#{testPharm1.pharmacyId}/stockarrivals/#{today}"
          .send testStockArrival
          .expect constants.http.CONFLICT, done

  describe "PUT /pharmacies/:id/stockarrivals/:date", () ->
    it "should return status OK if updated and increment stock levels", (done) ->
      saveDrug testDrug3, () ->
        pharmacies.saveStockArrivalDocument { id: testPharm1.pharmacyId, date: today }, testStockArrival, (status, result) ->
          status.should.equal constants.http.CREATED
          request service.app
            .put "/pharmacies/#{testPharm1.pharmacyId}/stockarrivals/#{today}"
            .send testStockArrivalUpdate
            .expect constants.http.OK
            .end (err, res) ->
              return done err if err
              test = (dbLevel, drugLevel) -> dbLevel.level.should.equal baseStockLevel + drugLevel.quantity
              checkStockLevels testPharm1, expectedStockArrivalAfterUpdate, test, done

    it "should return status NOT_FOUND if the pharmacy doesn't exist", (done) ->
      request service.app
        .put "/pharmacies/NOTTHERE/stockarrivals/#{today}"
        .send testStockArrival
        .expect constants.http.NOT_FOUND, done

    it "should return status BAD_REQUEST if the date is in the future", (done) ->
      request service.app
        .put "/pharmacies/#{testPharm1.pharmacyId}/stockarrivals/#{moment().add('days', 1).format('YYYYMMDD')}"
        .send testStockArrival
        .expect constants.http.BAD_REQUEST, done

    it "should return status BAD_REQUEST if the date malformed", (done) ->
      request service.app
        .put "/pharmacies/#{testPharm1.pharmacyId}/stockarrivals/BADDATE"
        .send testStockArrival
        .expect constants.http.BAD_REQUEST, done

    it "should return status NOT_FOUND if no stock arrival exists for the particular date", (done) ->
      request service.app
        .put "/pharmacies/#{testPharm1.pharmacyId}/stockarrivals/#{today}"
        .send testStockArrival
        .expect constants.http.NOT_FOUND, done

  # Drugs
 
  describe "GET /drugs/:drugCodeType/:drugCode", () ->
    it "should return status OK if found", (done) ->
      request service.app
        .get "/drugs/TEST/DRUG1"
        .expect "Content-Type", /json/
        .expect /"name": "Test Drug"/
        .expect constants.http.OK, done

    it "should return status NOT_FOUND if not found", (done) ->
      request service.app
        .get "/drugs/TEST/NOTTHERE"
        .expect constants.http.NOT_FOUND, done

  describe "POST /drugs", () ->
    it "should return status CREATED if created", (done) ->
      request service.app
        .post "/drugs"
        .send testDrug3
        .expect constants.http.CREATED
        .end (err, res) ->
          return done err if err
          drugs.getDrug {
            drugCode: testDrug3.identifiers[0].drugCode
            drugCodeType: testDrug3.identifiers[0].drugCodeType
          }, (status, result) ->
            status.should.equal constants.http.OK
            result.should.have.property "name", testDrug3.name
            done()

    it "should return status CONFLICT if drug with matching codes already exists", (done) ->
      request service.app
        .post "/drugs"
        .send testDrug1
        .expect constants.http.CONFLICT, done

  describe "PUT /drugs/:drugCodeType/:drugCode", () ->
    it "should return status OK if updated", (done) ->
      request service.app
        .put "/drugs/TEST/DRUG1"
        .send drugUpdate
        .expect constants.http.OK
        .end (err, res) ->
          return done err if err
          drugs.getDrug {
            drugCode: testDrug1.identifiers[0].drugCode
            drugCodeType: testDrug1.identifiers[0].drugCodeType
          }, (status, result) ->
            status.should.equal constants.http.OK
            result.should.have.property "name", testDrug1.name
            result.should.have.property "description", testDrug1.description
            result.should.have.property "minimumStockLevel", drugUpdate.minimumStockLevel
            done()

    it "should return status NOT_FOUND if drug does not exist", (done) ->
      request service.app
        .put "/drugs/TEST/NOTTHERE"
        .send drugUpdate
        .expect constants.http.NOT_FOUND, done

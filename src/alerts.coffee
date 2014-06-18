request = require "request"
moment = require "moment"
config = require "./config"
pharmacies = require "./pharmacies"
mongo = require "./mongo"

exports.sendAlert = (alert, callback) ->
  conf = config.getConf()
  url = "http://#{conf.him.host}:#{conf.him.port}/#{conf.alertsPath}"
  config.getLogger().info "Sending alert to HIM: #{url}"

  options = {
    url: url
    auth:
      user: conf.him.user
      pass: conf.him.password
    json:
      date: moment().format("YYYY-MM-DD")
      level: "1"
      message: "Stock levels low"
      user:
        clinicCode: alert.pharmacyId
      drug:
        barcode: alert.barcode
  }

  request.post options, (err, res, body) ->
    return callback err if err
    config.getLogger().info "Successfully sent alert for pharmacy #{alert.pharmacyId}"
    config.getLogger().info "Response: #{body}"
    callback null

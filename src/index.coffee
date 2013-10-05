async = require 'async'
nodejitsu = require 'nodejitsu-api'

propagate = (onErr, onSucc) -> (err, rest...) -> if err? then onErr(err) else onSucc(rest...)

exports.create = ({ username, password }) ->

  client = nodejitsu.createClient
    username: username
    password: password
    remoteUri: 'https://api.nodejitsu.com'

  create: (conf, callback) ->
    minutesToLive = conf.minutesToLive ? 20
    pack = conf.pack
    tag = conf.tag ? 'default'
    log = conf.log
    environment = conf.environment ? {}

    if !pack
      throw new Error("Missing pack")
    if tag.indexOf('-') != -1
      throw new Error("The tag cannot contain a dash")

    logLine = (str) ->
      return if !log
      log.write(str)
      log.write('\n')

    now = new Date()
    expiry = now.getTime() + 1000 * 60 * minutesToLive
    readableName = now.getMinutes() + '_' + now.getSeconds()
    name = tag + '-' + expiry + '-' + readableName
    version = '0.0.1'

    client.apps.list propagate callback, (apps) ->

      toPurge = apps.filter (app) ->
        [prefix, timestamp] = app.name.split('-')
        parseInt(timestamp) < now.getTime()

      logLine "Purging #{toPurge.length} of #{apps.length} apps..."
      async.forEach toPurge, (app, callback) ->
        client.apps.destroy(app.name, callback)
      , propagate callback, ->

        logLine "Creating app #{name}..."
        client.apps.create {
          version: version
          subdomain: name
          name: name
          env: environment
        }, propagate callback, ->
          logLine "Uploading snapshot..."
          client.snapshots.create name, version, pack, propagate callback, ->
            logLine "Activating snapshot..."
            client.snapshots.activate name, version, propagate callback, ->
              logLine "Starting app..."
              client.apps.start name, propagate callback, ->
                logLine "Live!"
                callback(null, { host: "https://#{name}.jit.su", appName: name })

  destroyAll: (tag, callback) ->
    client.apps.list propagate callback, (apps) ->
      matches = apps.filter (app) ->
        parts = app.name.split('-')
        parts.length == 3 && parts[0] == tag
      async.forEach matches, (app, callback) ->
        client.apps.destroy(app.name, callback)
      , callback

  destroy: (data, callback) ->
    client.apps.list propagate callback, (apps) ->
      matches = apps.filter (x) -> x.name == data.appName
      if matches.length > 1 then return callback(new Error("Too many matches"))
      if matches.length == 0 then return callback()
      client.apps.destroy(data.appName, callback)

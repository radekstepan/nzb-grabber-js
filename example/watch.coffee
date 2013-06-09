#!/usr/bin/env coffee
fs     = require 'fs'
watchr = require 'watchr'
log    = require 'node-logging'

NzbGrabber = require '../src/grabber.coffee'

# Init.
grabber = new NzbGrabber require '../config.json'

# Watching a directory for new nzb files.
watchr.watch
    'path': __dirname + '/nzbs'
    'listeners':
        'error': log.err
        'change': (type, path, stat) ->
            if type is 'create' and not stat.isDirectory()
                if path.match /\.nzb$/i
                    name = path.split('/').pop()
                    fs.readFile path, 'utf-8', (err, nzb) ->
                        log.inf 'Job ' + name.bold + ' queued'
                        # Grab them.
                        grabber.grab nzb, (err, filename, chunk, done) ->
                            return log.bad err if err

                            # And write them (they arrive in order).
                            fs.appendFile __dirname + '/downloads/' + filename, chunk, (err) ->
                                return log.bad err if err
                                log.inf 'Job ' + name.bold + ' done \u2713' if done
#!/usr/bin/env coffee
fs          = require 'fs'
assert      = require 'assert'
buffertools = require 'buffertools'
async       = require 'async'

UsenetServer = require './server.coffee'
NzbGrabber = require '../src/grabber.coffee'

module.exports =  
    'Multipart package': (cb) ->
        # New server.
        server = new UsenetServer()

        # Capture errors here.
        server.error cb

        # Listen for incoming connections.
        server.listen (err, port) ->
            return cb err if err

            # New client.
            client = new NzbGrabber
                'host': 'localhost'
                'port': port,
                'conn': 1

            # Here be files as we receive them.
            files = {}

            # Load the nzb file.
            fs.readFile __dirname + '/fixtures/multipart.nzb', 'utf-8', (err, nzb) ->
                return cb err if err
                client.grab nzb, (err, filename, chunk, done) ->
                    return cb err if err

                    # Push this chunk to the stack.
                    files[filename] ?= []
                    files[filename].push chunk

                    # Are we done with all of them?
                    if done
                        # Check the expected vs actual data.
                        async.each Object.keys(files), (filename, cb) ->
                            # Get the buffer as a merger of all chunks.
                            actual = Buffer.concat files[filename]
                            # Now get the expected file.
                            fs.readFile __dirname + '/fixtures/expected/' + filename, (err, expected) ->
                                return cb err if err
                                # Does it match?
                                assert.ok !expected.compare(actual), filename + \
                                    ' does not match; got ' + actual.length + ' bytes, expected ' + \
                                    expected.length + ' bytes'

                                # This file check out ok.
                                cb null
                        
                        , cb
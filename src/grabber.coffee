#!/usr/bin/env coffee
async       = require 'async'
log         = require 'node-logging'
NNTPWorker  = require './nntp.coffee'
nzb         = require './nzb.coffee'
yenc        = require './yenc.coffee'
buffertools = require 'buffertools'

class NzbGrabber

    # These are the workers with the head being the first available one.
    workers: []

    # Master queue of chunks to grab.
    queue: null

    # Just save the opts.
    constructor: (@opts) ->
        throw 'No conections' if !@opts.conn

        # Create workers of n concurrent connections.
        workers = ( new NNTPWorker(@opts) for i in [0...@opts.conn] )

        # Create an async queue running a chunk job.
        @queue = async.queue ({ group, article }, cb) ->
            # Get the first ready worker.
            for worker in workers
                unless worker.state is 'BUSY'
                    # Over to you monkey.
                    return worker.getArticle group, article, cb

        # Concurrency of n.
        , @opts.conn

    ###
    Grab files specified in the input NZB package.
    @param {String} NZB file as a string from `fs.readFile`
    @param {Function} A callback called on an error or on a chunk processed.
        @param {String} Error
        @param {String} Filename as specified in the article received.
        @param {Buffer} A decoded chunk for you to deal with.
        @param {Boolean} Are we finished with the package?
    @return {void}
    ###
    grab: (input, cb) ->
        self = @

        # Parse the input file.
        async.waterfall [ (cb) ->
            nzb input, cb

        # For each file to download (series).
        , (files, cb) ->
            # How many files to do still.
            todo = files.length

            files.forEach (file) ->
                # This will be our filename (from the article).
                filename = null
                # Cache of processed chunks (to preserve order and when we do not have a filename yet).
                cache = []
                # How many chunks to do still.
                chunks = file.length

                # For each chunk.
                file.forEach (chunk, i) ->
                    # Schedule to download this chunk in parallel.
                    # Need to return them in order so as to easily append to the end of files.
                    self.queue.push chunk, (err, code, buffer) ->
                        log.inf 'Article ' + chunk.article.bold + ' received'

                        # If not found...
                        if err or not buffer
                            log.err chunk.subject.bold + ' (' + (i + 1) + '/' + file.length + ') missing'
                            # Create a buffer of size and fill with zeroes.
                            decoded = (new Buffer(chunk.bytes)).fill 0
                        else
                            # yEnc decode (sync, no complaints, errors fixed by par2).
                            [ filename, decoded ] = yenc buffer
                        
                        # Push to cache at a position either way.
                        cache[i] = decoded
                        chunks -= 1 # one less to do

                        # Cache it if we do not have a filename yet.
                        unless filename
                            # Completely useless file?
                            if !chunks
                                cache = null
                                cb 'Useless file ' + chunk.subject
                        else
                            # Call back with an unbroken sequence of chunks from the start.
                            j = 0
                            while j <= file.length
                                # Get the item.
                                item = cache[j]
                                # Return if no chunks to return (break in the chain).
                                return unless item
                                # Move the index.
                                j += 1
                                # Continue if something was here (still unbroken chain).
                                continue if typeof(item) is 'boolean'
                                
                                # Logging of the chunk returned.
                                # Which chunk is this?
                                seg = ''
                                if file.length isnt 1 then seg = ' (' + j + '/' + file.length + ')'
                                # Is the size unexpected?
                                if file[j - 1].bytes isnt item.length
                                    log.err 'File ' + filename.bold + seg + ' done ' + item.length + ' bytes, expected ' + file[j - 1].bytes + ' bytes'
                                else
                                    log.inf 'File ' + filename.bold + seg + ' done ' + item.length + ' bytes'
                                
                                # Done = no more chunks cache and no more files.
                                cb null, filename, item, !chunks and !(todo -= 1)
                                # Say this part was already returned.
                                cache[j - 1] = yes

        ], cb

module.exports = NzbGrabber
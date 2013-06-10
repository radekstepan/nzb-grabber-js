#!/usr/bin/env coffee
async       = require 'async'
log         = require 'node-logging'
NNTPWorker  = require './nntp.coffee'
nzb         = require './nzb.coffee'
yenc        = require './yenc.coffee'
buffertools = require 'buffertools'

class NzbGrabber

    # Just save the opts.
    constructor: (@opts) ->
        throw 'No conections' if !@opts.conn

        # Create workers of n concurrent connections.
        workers = ( new NNTPWorker(@opts) for i in [0...@opts.conn] )

        self = @

        # The queue of jobs.
        @queue = do ->
            # Internal.
            q = []

            # Get a job from the head of the queue.
            'next': ->
                # Take the head.
                if task = q[0]
                    # Expand.
                    [ group, article, callback ] = task
                    # Do we have any workers ready?
                    for worker in workers when worker.state isnt 'BUSY'
                        # OK, so this task is now gone.
                        q.shift()
                        # Over to you monkey.
                        return worker.getArticle group, article, (err, code, buffer) ->
                            # Call back.
                            callback err, buffer
                            # Call the next job maybe?
                            self.queue.next()

            # Push a job to the stack.
            'push': (chunk, callback) ->
                # Queue the job.
                q.push [ chunk.group, chunk.article, callback ]
                # Do at least one job.
                self.queue.next()

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
            # How many chunks to do across all files? Increase when traversing files.
            todo = 0

            files.forEach (file) ->
                # This will be our filename (from the article).
                filename = null
                # Cache of processed chunks (to preserve order and when we do not have a filename yet).
                cache = []
                # How many chunks to do still.
                todo += chunks = file.length

                # For each chunk.
                file.forEach (chunk, i) ->
                    # Schedule to download this chunk in parallel.
                    # Need to return them in order so as to easily append to the end of files.
                    self.queue.push chunk, (err, buffer) ->
                        # If not found...
                        unless buffer
                            log.err chunk.subject.bold + ' (' + (i + 1) + '/' + file.length + ') missing'
                            # Create a buffer of size and fill with zeroes (sometimes nzb is incorrect though!).
                            decoded = (new Buffer(chunk.bytes)).fill 0
                        else
                            log.inf chunk.subject.bold + ' (' + (i + 1) + '/' + file.length + ') received'
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
                                seg = ''
                                if file.length isnt 1 then seg = ' (' + j + '/' + file.length + ')'
                                log.inf 'File ' + filename.bold + seg + ' done'
                                
                                # Done = no more chunks cache and no more files.
                                cb null, filename, item, !(todo -= 1)
                                # Say this part was already returned.
                                cache[j - 1] = yes

        ], cb

module.exports = NzbGrabber
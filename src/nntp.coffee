#!/usr/bin/env coffee
net         = require 'net'
log         = require 'node-logging'
stream      = require 'stream'
async       = require 'async'
buffertools = require 'buffertools'

# Just a counter of workers created.
id = 0

# A single conenction worker.
class NNTPWorker

    # Our worker is state. Offline/Ready/Busy
    state: 'OFFLINE'

    # Last error to have happened on our worker.
    error: null

    # The group we are currently connected to.
    group: null

    constructor: (@opts) ->
        self = @

        # I am me.
        @id = id++

        log.inf '#' + @id + ': Thread started'

        # Init the queueing mechanism (for command callbacks, not downloads!).
        @callbacks = do ->
            # Queue of callbacks.
            q = []

            # Get the head of the queue.
            'call': (code, res) ->
                if item = q.shift()
                    if typeof item isnt 'function'
                        throw 'Callback is not a function' # internal
                    
                    item self.error, code, res

            # Push a handler to the stack.
            'add': (callback) -> q.push callback

    # Connect to a server & auth. Calls back when ready.
    connect: (cb) =>
        self = @

        log.inf '#' + @id + ': Connecting to ' + @opts.host

        # Push the initial "200 Ready" callback to the queue.
        @callbacks.add ->
            # Skip auth?
            if !self.opts.user and !self.opts.pass
                cb null
                return

            # Send user.
            async.waterfall [ (cb) ->
                self.mode = 'MESSAGE'
                self.sendCommand 'AUTHINFO USER ' + self.opts.user, 381, cb
            
            # Send password.
            , (code, res, cb) ->
                self.mode = 'MESSAGE'
                self.sendCommand 'AUTHINFO PASS ' + self.opts.pass, 2, cb

            ], (err) ->
                # If an error has happened, save it for the next queue cb.
                self.error = err if err

                # We are ready to process other items on a queue (if any).
                cb null

        # The next (unrequested) response back will be a simple message.
        @mode = 'MESSAGE'

        # Initial connect, async of course.
        @client = net.connect
            'host': @opts.host
            'port': @opts.port
        , ->
            log.inf '#' + self.id + ': Client connected'

        # Fin. Idle timeout most likely.
        @client.on 'end', ->
            log.inf '#' + self.id + ': Client disconnected'
            self.ready = 0 # offline
            self.group = null  # no group
            self.client.destroy() # die
            self.client = null # no client

        # Network errors. Save them so that we can use them in callbacks.
        @client.on 'error', (err) ->
            self.error = err

        # Listen for data received.
        @client.on 'data', @onData

    # Send a command and callback with a result.
    # The response will have the trailing "\r\n." chopped off and will be a join of all the data received.
    sendCommand: (command, expected, callback) ->
        # Params.
        if typeof expected is 'function'
            callback = expected
            expected = null
        else
            # Turn the expected code into a regex.
            pattern = [ '\\d', '\\d', '\\d' ]
            ( pattern[i] = p for i, p of String(expected).split('') )
            expected = new RegExp '^' + pattern.join('') + '$'

        # Do we expect a particular res code pattern? Prefix with our callback.
        if expected
            @callbacks.add (err, code, buffer) ->
                # You have bigger problems to worry about buddy...
                return callback err if err
                # Matches the response code pattern?
                return callback code + ' does not match ' + expected unless code.match expected
                # Business as usual.
                callback null, code, buffer
        else
            # Set our callback in a queue.
            @callbacks.add callback

        # Clear the code, the first data to be received will have the code.
        @code = null

        # Say what will happen.
        log.dbg '#' + @id + ':' + ' >> '.bold + command

        # Make the request (client will be instantiated by now).
        @client.write command + '\r\n'
    
    # What do you do with data?
    # message = [code] \r\n
    # article = [headers] + \r\n\r\n + [body] + \r\n.\r\n
    onData: (buffer) =>
        # Get code.
        getCode = ->
            buffer.toString 'ascii', 0, 3
        
        # Does the article end now?
        isArticleEnd = ->
            length = buffer.length
            buffer.toString('ascii', length - 5) is '\r\n.\r\n'

        # Remove headers and the trailing dot on input.
        removeHeaders = (input) ->
            length = input.length
            input.slice input.indexOf('\r\n\r\n') + 4, length - 3

        # What mode are we in?
        switch @mode
            # Simple response message.
            when 'MESSAGE'
                # Just respond.
                length = buffer.length
                res = buffer.slice 0, length - 2 # sans trailing newline
                log.dbg '#' + @id + ': << ' + res.toString() # log it too
                @callbacks.call getCode(), res
            
            # Beginning of an article.
            when 'ARTICLE_BEGIN'
                # Get the code.
                @code = getCode()

                # Missing article?
                if @code is '430'
                    @state = 'READY' # ready again
                    # Early bath for him.
                    @callbacks.call @code, null
                    return
                
                # Does the article end now?
                if isArticleEnd()
                    @state = 'READY' # ready again
                    # Clean & call any handler that is listening.
                    @callbacks.call @code, removeHeaders buffer
                else
                    @mode = 'ARTICLE_CONTINUE'
                    @article = [ buffer ]

            # We continue to receive the article.
            when 'ARTICLE_CONTINUE'
                @article.push buffer
                # Does the article end now?
                if isArticleEnd()
                    @state = 'READY' # ready again
                    # Join, clean & call any handler that is listening.
                    @callbacks.call @code, removeHeaders Buffer.concat @article

    ###
    Get an article in a group.
    @param {String} Group name.
    @param {String} Article id.
    @param {Function} A callback called on an error or article decoded (once).
        @param {String} Error
        @param {Buffer} An article buffer for you to deal with (undecoded) or null if not found.
    @return {void}
    ###
    getArticle: (group, article, cb) ->
        self = @

        # Select a group.
        sendGroup = (cb) ->
            self.mode = 'MESSAGE'
            self.group = group # now we are on this group
            self.sendCommand 'GROUP ' + group, 2, ->
                cb null

        # Grab the article.
        sendArticle = (cb) ->
            # Do we need to pad the message id?
            article = '<' + article + '>' unless article.match /^<(\S*)>$/

            self.mode = 'ARTICLE_BEGIN'
            self.sendCommand 'ARTICLE ' + article, 2, cb

        # Are we offline?
        if @state is 'OFFLINE'
            steps = [ @connect, sendGroup, sendArticle ]
        else
            # Change groups?
            if @group isnt group
                steps = [ sendGroup, sendArticle ]
            else
                steps = [ sendArticle ]

        # Now we are busy.
        @state = 'BUSY'

        # Run these steps.
        async.waterfall steps, cb

module.exports = NNTPWorker
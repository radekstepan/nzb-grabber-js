#!/usr/bin/env coffee
fs  = require 'fs'
net = require 'net'

# Close each command with this.
end = '\r\n'

# A mock Usenet Server piping whichever test files we want. 
class UsenetServer

    constructor: ->
        @server = new net.Server()

    # Listen returning the port assigned.
    listen: (cb) ->
        self = @
        # On connection.
        @server.on 'connection', @onConnection
        # When listening.
        @server.on 'listening', -> cb null, self.server.address().port
        # Listen.
        @server.listen()

    onConnection: (socket) ->
        socket.write 'Welcome to a test Usenet server' + end

        # Handle requests.
        socket.on 'data', (data) ->
            [ command, param ] = data.toString().split(' ')
            # Which command and params?
            switch command
                when 'GROUP'
                    socket.write '200 Whatever you say' + end
                when 'ARTICLE'
                    # Get the article requested.
                    article = param[1...- 3] # ends with \r\n too
                    # Load it.
                    fs.readFile __dirname + '/fixtures/articles/' + article, (err, buffer) ->
                        return socket.write '430 Article not found' + end if err
                        # Respond with the article wrapper in headers.
                        socket.write Buffer.concat [ new Buffer('200 Here you go mate' + end), buffer, new Buffer('.\r\n') ]

    # Expose error handler.
    error: (cb) ->
        @server.on 'error', cb

module.exports = UsenetServer
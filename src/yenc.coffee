#!/usr/bin/env coffee
crc32   = require 'buffer-crc32'
log     = require 'node-logging'

# Generate charcodes for us.
c = {} ; ( c[char] = char.charCodeAt(0) for char in [ '.', '\n', '\r', '=' ] )

# https://github.com/jkv/nzb-o-matic-plus/blob/790b3444e5698a891e1a9e4fb7cefb385ec47273/Decoder.cs#L533-L553
module.exports = (input) ->
    line = []

    # Hope this will get filled in.
    filename = null

    # The buffer will be at most this size minus 3 header lines and some double dots.
    buffer = new Buffer(input.length) ; i = 0

    processLine = ->
        return if line.length is 0

        # Skip one of two leading dots.
        if line[0] is line[1] is c['.'] then line.shift()

        # Skip headers?
        stringy = new Buffer(line[0...7]).toString()
        if match = stringy.match /^\=(ybegin|ypart|yend)/
            switch match[1]
                when 'ybegin'
                    if match = new Buffer(line).toString().match /name\=([^\s]*)/
                        filename = match[1]

                when 'yend'
                    # We are done, slice the buffer.
                    buffer = buffer.slice 0, i
                    # Do we have a CRC check?
                    if pcrc32 = new Buffer(line).toString().match /pcrc32\=([^\s]*)/
                        if (calc = (crc32.unsigned(buffer)).toString(16)) isnt pcrc32[1]
                            log.err 'File ' + filename.bold + " crc fail, expected #{pcrc32[1]} got #{calc}"

            return

        # No longer needed.
        stringy = null

        escape = no
        # CharArray.
        for code in line           
            # Critical flag.
            if code is c['='] and not escape
                escape = true
            else
                # Special escaping needed.
                if escape
                    code -= 64
                    escape = false

                code -= 42
                buffer[i++] = code

    # Process line by line.
    j = 0 ; length = input.length
    while j < length
        # Read the char from the buffer.
        code = input[j++]

        # Process the line after a newline.
        if code in [ c['\n'], c['\r'] ]
            processLine()
            line = []
            continue
        line.push code

    processLine()

    # Input is no longer needed.
    input = null

    # Call back.
    [ filename, buffer ]
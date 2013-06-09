#!/usr/bin/env coffee
async = require 'async'
xml   = require 'xml2js'
fs    = require 'fs'

###
Parse an NZB file.
@param {String} NZB file as a string from `fs.readFile`
@param {Function} A callback called with an Array of Array of articles to download.
    @param {String} Error
    @param {Array} Of files to articles (ordered).
@return {void}
###
module.exports = (input, cb) ->
    # XML parse.
    async.waterfall [ (cb) ->
        xml.parseString input, cb

    # Order the segments in each file.
    (obj, cb) ->
        async.map obj.nzb.file, (file, cb) ->
            # Subject for info purposes.
            subject = file.$.subject

            # Which group?
            group = file.groups[0].group[0]
            # Get the segments.
            segments = []
            for segment in file.segments[0].segment
                # Ordered segments starting with 0.
                segments[parseInt(segment.$.number) - 1] =
                    'group': group
                    'article': segment._
                    'bytes': parseInt segment.$.bytes
                    'subject': subject

            cb null, segments

        , cb

    ], cb

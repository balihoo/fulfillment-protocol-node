crypto = require 'crypto'
zlib = require 'zlib'
Promise = require 'bluebird'
S3Adapter = require('./s3Adapter').S3Adapter
startsWith = require('./utils').startsWith
Promise.promisifyAll zlib

exports.MAX_RESULT_SIZE = MAX_RESULT_SIZE = 32768
exports.ZIP_PREFIX = ZIP_PREFIX = 'FF-ZIP'
exports.URL_PREFIX = URL_PREFIX = 'FF-URL'
exports.SEPARATOR = SEPARATOR = ':'

s3dir = 'retain_30_180/zipped-ff'

hash = (data) ->
  md5sum = crypto.createHash 'md5'
  md5sum.update data
  md5sum.digest 'hex'

byteLength = (str) ->
  Buffer.byteLength str, 'utf8'

zip = (data) ->
  zlib.deflateAsync data
  .then (compressed) ->
    encoded = new Buffer compressed
    .toString 'base64'

    "#{ZIP_PREFIX}#{SEPARATOR}#{byteLength data}#{SEPARATOR}#{encoded}"

unzip = (data) ->
  parts = data.split SEPARATOR
  throw new Error "Malformed zip data"  if parts.length isnt 3

  encoded = parts[2]
  compressed = new Buffer encoded, 'base64'

  zlib.inflateAsync compressed
  .then (decompressed) ->
    decompressed.toString 'utf-8'

storeInS3 = (data, s3Adapter) ->
  hash = hash data

  s3Adapter.upload "#{s3dir}/#{hash}.ff", data
  .then (uri) ->
    "#{URL_PREFIX}#{SEPARATOR}#{hash}#{SEPARATOR}#{uri}"

exports.DataZipper = class DataZipper
  constructor: (opts) ->
    @s3Adapter = opts.s3Adapter or new S3Adapter bucket: opts.bucket

  getFromUrl: (ff_url) ->
    parts = ff_url.split SEPARATOR
    throw new Error "Malformed URL #{ff_url}"  if parts.length isnt 4

    protocol = parts[2]
    path = parts[3]
    uri = "#{protocol}:#{path}"

    throw Error "DataZipper only supports s3 protocol for fulfillment documents" unless protocol is "s3"

    @s3Adapter.download uri
    .then (s3Result) ->
      s3Result.Body?.toString 'utf-8'

  deliver: (workResult) =>
    Promise.try =>
      return unless workResult?

      stringResult = JSON.stringify workResult
      return workResult if byteLength(stringResult) < MAX_RESULT_SIZE

      # Result is too big, compress and base64 encode it
      zip stringResult
      .then (zipResult) =>
        return zipResult if byteLength(zipResult) < MAX_RESULT_SIZE

        # Zipped result is still too big, so put it in S3
        storeInS3 zipResult, @s3Adapter

  receive: (ff_url) =>
    Promise.try =>
      if typeof ff_url is 'string'
        if startsWith ff_url, ZIP_PREFIX
          unzip ff_url
          .then (unzipped) ->
            JSON.parse unzipped
        else if startsWith ff_url, URL_PREFIX
          @getFromUrl ff_url
          .then (result) =>
            @receive result
        else
          # It isn't an ZIP or URL, so just return the string
          return ff_url
      else
        # It isn't a string, so return it
        return ff_url

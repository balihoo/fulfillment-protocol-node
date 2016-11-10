assert = require 'assert'
sinon = require 'sinon'
aws = require 'aws-sdk'
S3Adapter = require('../src/s3Adapter').S3Adapter
mockS3 = require './mocks/mockS3'
dataZipper = require '../src/dataZipper'

bigTestData = require './bigTestData.json'
biggerTestData = require './biggerTestData.json'

fakeBucket = 'some.bucket'

smallResult =
  stuff: 'things'

describe 'dataZipper unit tests', ->
  describe 'deliver() / receive()', ->
    context "when an s3 adapter is passed to the constructor", ->
      it "uses it", ->
        fakeS3Adapter = { "I'm": "a fake s3 adapter!" }
        zipper = new dataZipper.DataZipper s3Adapter: fakeS3Adapter
        assert.strictEqual zipper.s3Adapter, fakeS3Adapter

    context "when no s3 adapter is passed to the constructor", ->
      it "creates its own", ->
        zipper = new dataZipper.DataZipper bucket: fakeBucket
        assert zipper.s3Adapter instanceof S3Adapter
        assert.strictEqual zipper.s3Adapter.bucket, fakeBucket

    context "when the supplied data is less than #{dataZipper.MAX_RESULT_SIZE} bytes", ->
      it 'returns the supplied data', ->
        zipper = new dataZipper.DataZipper {}

        zipper.deliver smallResult
        .then (result) ->
          assert.strictEqual result, smallResult

          zipper.receive smallResult
        .then (result) ->
          assert.strictEqual result, smallResult

    context "when the supplied data is greater than #{dataZipper.MAX_RESULT_SIZE} bytes", ->
      context "and the compressed data is less than #{dataZipper.MAX_RESULT_SIZE} bytes", ->
        it 'returns a compressed and base64-encoded string', ->
          zipper = new dataZipper.DataZipper {}

          expectedStart = dataZipper.ZIP_PREFIX + dataZipper.SEPARATOR

          zipper.deliver bigTestData
          .then (encodedResult) ->
            assert typeof encodedResult is 'string'
            assert encodedResult.slice(0, expectedStart.length) is expectedStart

            zipper.receive encodedResult
          .then (decodedResult) ->
            assert.deepEqual decodedResult, bigTestData

      context "and the compressed data is greater than #{dataZipper.MAX_RESULT_SIZE} bytes", ->
        it 'returns an S3 URL', ->
          uploadedData = null
          sinon.stub aws, 'S3', mockS3

          s3Adapter = new S3Adapter
            bucket: fakeBucket

          zipper = new dataZipper.DataZipper s3Adapter: s3Adapter
          expectedStart = dataZipper.URL_PREFIX + dataZipper.SEPARATOR

          zipper.deliver biggerTestData
          .then (s3Result) ->
            assert.strictEqual s3Adapter.s3.config.params.Bucket, fakeBucket
            assert s3Adapter.s3.upload.calledOnce
            assert s3Adapter.s3.upload.calledWith
              Key: "retain_30_180/zipped-ff/20164bb1b885c2ff4de9b4c73c557e6c.ff"
              Body: sinon.match dataZipper.ZIP_PREFIX + dataZipper.SEPARATOR

            call = s3Adapter.s3.upload.getCall 0
            key = call.args[0].Key
            uploadedData = call.args[0].Body

            assert typeof s3Result is 'string'
            assert s3Result.slice(0, expectedStart.length) is expectedStart


            s3Adapter.s3.getObject = sinon.spy (params, callback) ->
              if params.Key is key
                callback null, Body: uploadedData
              else
                callback new Error "Unknown key #{params.Key} isnt #{key}"

            zipper.receive s3Result
          .then (decodedResult) ->
            assert.deepEqual decodedResult, biggerTestData



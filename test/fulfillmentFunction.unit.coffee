Promise = require "bluebird"
fulfillmentFunction = require "../src/fullfillmentFunction"
sinon = require "sinon"
assert = require "assert"
error = require "../src/error"
activityStatus = require "../src/activityStatus"

describe "FulfillmentFunction unit tests", ->
  context "when fulfillment protocol is enabled", ->
    context "and the handler runs successfully", ->
      it "calls dataZipper.deliver and context.succeed with the result + success status", ->
        context =
          succeed: sinon.spy()
          fail: (err) -> throw err

        handlerResult =
          "some": "result"

        expectedResult =
          status: activityStatus.SUCCESS
          result: handlerResult

        event =
          "some": "input"

        f = new fulfillmentFunction.FulfillmentFunction
          schema: params: {}
          handler: (input) ->
            assert.strictEqual input, event
            handlerResult

        sinon.stub f.dataZipper, 'deliver', sinon.spy (input) -> Promise.resolve input

        f.handle event, context
        .then ->
          assert f.dataZipper.deliver.calledOnce
          assert f.dataZipper.deliver.calledWith expectedResult
          assert context.succeed.calledOnce
          assert context.succeed.calledWith expectedResult

    context "and the handler throws an error of unknown type", ->
      it "wraps the error in a FulfillmentUnhandledError and sends an error payload to context.succeed", ->
        errMessage = "Loud Noises!"
        err = new Error errMessage
        unknownErrMessage = "unhandled exception: #{errMessage}"

        context =
          succeed: sinon.spy()
          fail: (err) -> throw err

        event =
          "some": "input"

        expectedResult =
          status: activityStatus.FAILED
          notes: []
          reason: unknownErrMessage
          result: unknownErrMessage
          trace: err.stack.split "\n"

        f = new fulfillmentFunction.FulfillmentFunction
          schema: params: {}
          handler: (input) ->
            throw err

        f.handle event, context
        .then ->
          assert context.succeed.calledOnce
          assert.deepEqual expectedResult, context.succeed.firstCall.args[0]

    context "and the handler throws an error which extends FulfillmentError", ->
      it "uses the error's responseCode method to get the status to send", ->
        innerErrorMessage = "Loud Noises!"
        innerError = new Error innerErrorMessage

        deferErrorMessage = "deferred"
        deferError = new error.FulfillmentDeferError deferErrorMessage, innerError

        combinedErrorMessage = "#{deferErrorMessage}: #{innerErrorMessage}"

        context =
          succeed: sinon.spy()
          fail: (err) -> throw err

        event =
          "some": "input"

        expectedResult =
          status: activityStatus.DEFER
          notes: []
          reason: combinedErrorMessage
          result: combinedErrorMessage
          trace: deferError.stack.split "\n"

        f = new fulfillmentFunction.FulfillmentFunction
          schema: params: {}
          handler: (input) ->
            throw deferError

        f.handle event, context
        .then ->
          assert context.succeed.calledOnce
          assert.deepEqual expectedResult, context.succeed.firstCall.args[0]

  context "when fulfillment protocol is disabled by the function author", ->
    it "calls the handler with the event and calls context.succeed with the result", ->
      context =
        succeed: sinon.spy()
        fail: (err) -> throw err

      expectedResult =
        "some": "result"

      event =
        "some": "input"

      f = new fulfillmentFunction.FulfillmentFunction
        schema: params: {}
        disableProtocol: true
        handler: (input) ->
          assert.strictEqual input, event
          expectedResult

      f.handle event, context
      .then ->
        assert context.succeed.calledOnce
        assert context.succeed.calledWith expectedResult

    context "and the handler function throws an error", ->
      it "calls context.fail with the error", ->
        context =
          succeed: -> throw new Error "Shouldn't have succeeded"
          fail: sinon.spy()

        err = new Error "Loud noises!"

        f = new fulfillmentFunction.FulfillmentFunction
          schema: params: {}
          disableProtocol: true
          handler: ->
            throw err

        event =
          "some": "input"

        f.handle event, context
        .then ->
          assert context.fail.calledOnce
          assert context.fail.calledWith err

    context "and the input fails to validate", ->
      it "calls context.fail with the validation error", ->
        context =
          succeed: -> throw new Error "Shouldn't have succeeded"
          fail: sinon.spy()

        f = new fulfillmentFunction.FulfillmentFunction
          schema:
            params:
              type: "object"
              properties:
                stuff: type: "string"
              required: ["stuff"]
          disableProtocol: true
          handler: sinon.spy()

        event =
          "some": "input"

        f.handle event, context
        .then ->
          assert.equal f.handler.callCount, 0
          assert context.fail.calledOnce

          err = context.fail.firstCall.args[0]
          assert err instanceof error.FulfillmentValidationError
          assert.equal err.message, 'Error validating input: requires property "stuff"'

  context "when schema validation is disabled", ->
    it "bypasses schema validation", ->
      context =
        succeed: sinon.spy()
        fail: (err) -> throw err

      expectedResult =
        "some": "result"

      f = new fulfillmentFunction.FulfillmentFunction
        schema:
          params:
            type: "object"
            properties:
              stuff: type: "string"
            required: ["stuff"]
        disableProtocol: true
        disableSchemaValidation: true
        handler: -> expectedResult

      event =
        "some": "input"

      f.handle event, context
      .then ->
        assert context.succeed.calledOnce
        assert context.succeed.calledWith expectedResult

  context "when fulfillment protocol is disabled by the event", ->
    it "calls the handler with the event and calls context.succeed with the result", ->
      context =
        succeed: sinon.spy()
        fail: (err) -> throw err

      expectedResult =
        "some": "result"

      event =
        "some": "input"

      event[fulfillmentFunction.commands.DISABLE_PROTOCOL] = true

      f = new fulfillmentFunction.FulfillmentFunction
        schema: params: {}
        disableProtocol: false
        handler: (input) ->
          assert.strictEqual input, event
          expectedResult

      f.handle event, context
      .then ->
        assert context.succeed.calledOnce
        assert context.succeed.calledWith expectedResult

  context "when the event includes the #{fulfillmentFunction.commands.LOG_INPUT} command", ->
    it "logs the event", ->
      context =
        succeed: sinon.spy()
        fail: (err) -> throw err

      m = null
      sinon.stub console, "log", (message) ->
        m = message

      handlerResult =
        "some": "result"

      expectedResult =
        status: activityStatus.SUCCESS
        result: handlerResult

      event =
        "some": "input"

      event[fulfillmentFunction.commands.LOG_INPUT] = true

      f = new fulfillmentFunction.FulfillmentFunction
        schema: params: {}
        handler: (input) ->
          assert.strictEqual input, event
          handlerResult

      f.handle event, context
      .then ->
        console.log.restore()
        assert.equal m, JSON.stringify(event, null, 2)
        assert context.succeed.calledOnce
        assert context.succeed.calledWith expectedResult

  context "when the event includes the #{fulfillmentFunction.commands.LOG_CONTEXT} command", ->
    it "logs the context", ->
      context =
        succeed: sinon.spy()
        fail: (err) -> throw err
        some: "context"

      m = null
      sinon.stub console, "log", (message) ->
        m = message

      handlerResult =
        "some": "result"

      expectedResult =
        status: activityStatus.SUCCESS
        result: handlerResult

      event =
        "some": "input"

      event[fulfillmentFunction.commands.LOG_CONTEXT] = true

      f = new fulfillmentFunction.FulfillmentFunction
        schema: params: {}
        handler: (input) ->
          assert.strictEqual input, event
          handlerResult

      f.handle event, context
      .then ->
        console.log.restore()
        assert.equal m, JSON.stringify(context, null, 2)
        assert context.succeed.calledOnce
        assert context.succeed.calledWith expectedResult

  context "when the event includes the #{fulfillmentFunction.commands.RETURN_SCHEMA} command", ->
    it "calls context.succeed with the schema", ->
      context =
        succeed: sinon.spy()
        fail: (err) -> throw err

      event =
        "some": "input"

      schema =
        params:
          type: "object"
          properties:
            stuff: type: "string"
          required: ["stuff"]
        result:
          type: "object"
          properties:
            someResult: type: "string"
          required: ["someResult"]
        description: "This function does some stuff!"

      event[fulfillmentFunction.commands.RETURN_SCHEMA] = true

      f = new fulfillmentFunction.FulfillmentFunction
        schema: schema
        handler: sinon.spy()

      f.handle event, context
      .then ->
        assert context.succeed.calledOnce
        assert context.succeed.calledWith schema

  context "when the provided auth function returns a falsey result", ->
    it "calls context.fail with 'unauthorized'", ->
      context =
        succeed: -> throw new Error "Shouldn't have succeeded"
        fail: sinon.spy()

      f = new fulfillmentFunction.FulfillmentFunction
        schema: params: {}
        handler: sinon.spy()
        authenticator: -> 0

      event =
        "some": "input"

      f.handle event, context
      .then ->
        assert.equal f.handler.callCount, 0
        assert context.fail.calledOnce

        err = context.fail.firstCall.args[0]
        assert.equal err, "unauthorized"

  context "when the event is a string", ->
    it "calls dataZipper.receive to decode the event", ->
      context =
        succeed: sinon.spy()
        fail: (err) -> throw err

      handlerResult =
        "some": "result"

      expectedResult =
        status: activityStatus.SUCCESS
        result: handlerResult

      event = "FF-ZIP:some stuff" # Not a real FF-ZIP
      decodedEvent =
        some: "decodedobject"

      f = new fulfillmentFunction.FulfillmentFunction
        schema: params: {}
        handler: (input) ->
          assert.equal input, decodedEvent
          handlerResult

      sinon.stub f.dataZipper, "receive", (input) ->
        assert.equal input, event
        decodedEvent

      f.handle event, context
      .then ->
        f.dataZipper.receive.restore()
        assert context.succeed.calledOnce
        assert context.succeed.calledWith expectedResult
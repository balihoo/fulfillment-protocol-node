Promise = require "bluebird"
dataZipper = require "./dataZipper"
validate = require('jsonschema').validate
error = require "./error"
activityStatus = require "./activityStatus"

exports.commands = commands =
  RETURN_SCHEMA: "RETURN_SCHEMA"
  LOG_INPUT: "LOG_INPUT"
  LOG_CONTEXT: "LOG_CONTEXT"
  DISABLE_PROTOCOL: "DISABLE_PROTOCOL"

exports.FulfillmentFunction = class FulfillmentFunction
  constructor: (opts) ->
    @schema = opts.schema
    @handler = opts.handler
    @defaultError = opts.defaultError or error.FulfillmentUnhandledError
    @disableProtocol = opts.disableProtocol
    @disableSchemaValidation = opts.disableSchemaValidation
    @authenticator = opts.authenticator
    @dataZipper = new dataZipper.DataZipper bucket: opts.bucket

  validate: (input) ->
    result = validate input, @schema.params
    throw new error.FulfillmentValidationError "Error validating input", result.errors[0] if result.errors.length > 0

  handle: (event, context) ->
    disableProtocol = null

    handleResult = (result) =>
      Promise.try =>
        return result if disableProtocol

        @dataZipper.deliver result
        .then (maybeZippedResult) ->
          status: activityStatus.SUCCESS
          result: maybeZippedResult
      .then context.succeed

    handleError = (err) =>
      # Fail the lambda invocation with the error
      return context.fail err if disableProtocol

      unless err instanceof error.FulfillmentError
        err = new @defaultError "unhandled exception", err

      trace = []

      if err.stack
        if typeof err.stack is "string"
          trace = err.stack.split "\n"

      # Failures are still returned via succeed() but the status and payload articulate the error
      return context.succeed
        status: err.responseCode()
        notes: []
        reason: err.message
        result: err.message
        trace: trace

    Promise.try =>
      if typeof event is 'string'
        @dataZipper.receive event
      else
        event
    .then (input) =>
      eventKeys = Object.keys input

      if commands.LOG_INPUT in eventKeys
        console.log JSON.stringify input, null, 2

      if commands.LOG_CONTEXT in eventKeys
        console.log JSON.stringify context, null, 2

      # Just return the schema without protocol
      if commands.RETURN_SCHEMA in eventKeys
        disableProtocol = true
        return @schema

      # Any explicit protocol enable/disable from the event takes precedence
      disableProtocol = input[commands.DISABLE_PROTOCOL]
      # As a fall-back, check for a function-level option that dictates protocol use
      disableProtocol ?= @disableProtocol

      @validate input unless @disableSchemaValidation

      if @authenticator and not @authenticator input
        disableProtocol = true
        throw "unauthorized" # Don't change this string unless you also change the corresponding regex in API Gateway.

      @handler input
    .then handleResult
    .catch handleError

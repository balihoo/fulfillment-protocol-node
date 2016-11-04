activityStatus = require "./activityStatus"

exports.FulfillmentError = class FulfillmentError extends Error
  constructor: (message, @innerError, @notes) ->
    @name = @constructor.name

    if @innerError
      @stack = @innerError.stack
      message = "#{message}: #{@innerError.message}"

    @message = message

  responseCode: ->
    return if @fatal then activityStatus.FATAL else activityStatus.FAILED

exports.FulfillmentUnhandledError = class FulfillmentUnhandledError extends FulfillmentError
  responseCode: ->
    # Some node workers/lambda functions set this property to indicate fatal errors
    if @innerError?.fatal then activityStatus.FATAL else activityStatus.FAILED

exports.FulfillmentValidationError = class FulfillmentValidationError extends FulfillmentError
  """ Failure: A retry without fixing the input will not work """
  responseCode: ->
    activityStatus.INVALID

exports.FulfillmentFatalError = class FulfillmentFatalError extends FulfillmentError
  """ Fatal: A retry without fixing the input will not work """
  responseCode: ->
    activityStatus.FATAL

exports.FulfillmentFailedError = class FulfillmentFailedError extends FulfillmentError
  """ Failed: A retry might work """
  responseCode: ->
    activityStatus.FAILED

exports.FulfillmentDeferError = class FulfillmentDeferError extends FulfillmentError
  """ Cancel: Result not yet available, retry """
  responseCode: ->
    activityStatus.DEFER

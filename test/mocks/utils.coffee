sinon = require 'sinon'

exports.nodeLikeSuccessSpy = ->
  return sinon.spy (item, callback) ->
    callback null, true
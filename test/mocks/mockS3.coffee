nodeLikeSuccessSpy = require('./utils').nodeLikeSuccessSpy

module.exports = class MockS3
  constructor: (@config) ->
    
  upload: nodeLikeSuccessSpy()
  getObject: nodeLikeSuccessSpy()


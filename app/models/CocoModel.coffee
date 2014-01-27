storage = require 'lib/storage'

class CocoSchema extends Backbone.Model
  constructor: (path, args...) ->
    super(args...)
    @urlRoot = path + '/schema'

window.CocoSchema = CocoSchema

class CocoModel extends Backbone.Model
  idAttribute: "_id"
  loaded: false
  loading: false
  saveBackups: false
  @schema: null

  initialize: ->
    super()
    if not @constructor.className
      console.error("#{@} needs a className set.")
    @markToRevert()
    if @constructor.schema?.loaded
      @addSchemaDefaults()
    else
      @loadSchema()
    @once 'sync', @onLoaded, @
    @saveBackup = _.debounce(@saveBackup, 500)
    
  type: ->
    @constructor.className

  onLoaded: ->
    @loaded = true
    @loading = false
    @markToRevert()
    if @saveBackups
      existing = storage.load @id
      if existing
        @set(existing, {silent:true}) 
        CocoModel.backedUp[@id] = @
    
  set: ->
    res = super(arguments...)
    @saveBackup() if @saveBackups and @loaded
    res
    
  saveBackup: ->
    storage.save(@id, @attributes)
    CocoModel.backedUp[@id] = @
    
  @backedUp = {}

  loadSchema: ->
    unless @constructor.schema
      @constructor.schema = new CocoSchema(@urlRoot)
      @constructor.schema.fetch()

    @constructor.schema.on 'sync', =>
      @constructor.schema.loaded = true
      @addSchemaDefaults()
      @trigger 'schema-loaded'

  @hasSchema: -> return @schema?.loaded
  schema: -> return @constructor.schema

  validate: ->
    result = tv4.validateMultiple(@attributes, @constructor.schema?.attributes or {})
    if result.errors?.length
      console.log @, "got validate result with errors:", result
    return result.errors unless result.valid

  save: (attrs, options) ->
    options ?= {}
    success = options.success
    options.success = (resp) =>
      @trigger "save:success", @
      success(@, resp) if success
      @markToRevert()
      @clearBackup()
    @trigger "save", @
    return super attrs, options

  fetch: ->
    super()
    @loading = true

  markToRevert: ->
    @_revertAttributes = _.clone @attributes

  revert: ->
    @set(@_revertAttributes, {silent: true}) if @_revertAttributes
    @clearBackup()
    
  clearBackup: ->
    storage.remove @id

  hasLocalChanges: ->
    not _.isEqual @attributes, @_revertAttributes

  cloneNewMinorVersion: ->
    newData = $.extend(null, {}, @attributes)
    new @constructor(newData)

  cloneNewMajorVersion: ->
    clone = @cloneNewMinorVersion()
    clone.unset('version')
    clone

  isPublished: ->
    for permission in @get('permissions') or []
      return true if permission.target is 'public' and permission.access is 'read'
    false

  publish: ->
    if @isPublished() then throw new Error("Can't publish what's already-published. Can't kill what's already dead.")
    @set "permissions", (@get("permissions") or []).concat({access: 'read', target: 'public'})

  addSchemaDefaults: ->
    return if @addedSchemaDefaults or not @constructor.hasSchema()
    @addedSchemaDefaults = true
    for prop, defaultValue of @constructor.schema.attributes.default or {}
      continue if @get(prop)?
      #console.log "setting", prop, "to", defaultValue, "from attributes.default"
      @set prop, defaultValue
    for prop, sch of @constructor.schema.attributes.properties or {}
      continue if @get(prop)?
      #console.log "setting", prop, "to", sch.default, "from sch.default" if sch.default?
      @set prop, sch.default if sch.default?

  getReferencedModels: (data, schema, path='/') ->
    # returns unfetched model shells for every referenced doc in this model
    # OPTIMIZE so that when loading models, it doesn't cause the site to stutter
    data ?= @attributes
    schema ?= @schema().attributes
    models = []

    if $.isArray(data) and schema.items?
      for subData, i in data
        models = models.concat(@getReferencedModels(subData, schema.items, path+i+'/'))

    if $.isPlainObject(data) and schema.properties?
      for key, subData of data
        continue unless schema.properties[key]
        models = models.concat(@getReferencedModels(subData, schema.properties[key], path+key+'/'))

    model = CocoModel.getReferencedModel data, schema
    models.push model if model
    return models

  @getReferencedModel: (data, schema) ->
    return null unless schema.links?
    linkObject = _.find schema.links, rel: "db"
    return null unless linkObject
    return null if linkObject.href.match("thang_type") and not @isObjectID(data)  # Skip loading hardcoded Thang Types for now (TODO)

    # not fully extensible, but we can worry about that later
    link = linkObject.href
    link = link.replace('{(original)}', data.original)
    link = link.replace('{(majorVersion)}', '' + (data.majorVersion ? 0))
    link = link.replace('{($)}', data)
    @getOrMakeModelFromLink(link)

  @getOrMakeModelFromLink: (link) ->
    makeUrlFunc = (url) -> -> url
    modelUrl = link.split('/')[2]
    modelModule = _.string.classify(modelUrl)
    modulePath = "models/#{modelModule}"
    window.loadedModels ?= {}

    try
      Model = require modulePath
      window.loadedModels[modulePath] = Model
    catch e
      console.error 'could not load model from link path', link, 'using path', modulePath
      return

    model = new Model()
    model.url = makeUrlFunc(link)
    return model

  @isObjectID: (s) ->
    s.length is 24 and s.match(/[a-z0-9]/gi)?.length is 24

module.exports = CocoModel

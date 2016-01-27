RootView = require 'views/core/RootView'
forms = require 'core/forms'
TrialRequest = require 'models/TrialRequest'
AuthModal = require 'views/core/AuthModal'

formSchema = {
  type: 'object'
  required: ['name', 'email', 'organization']
  properties:
    name: { type: 'string', minLength: 1 }
    email: { type: 'string', format: 'email' }
    phoneNumber: { type: 'string' }
    role: { type: 'string' }
    organization: { type: 'string' }
    city: { type: 'string' }
    state: { type: 'string' }
    country: { type: 'string' }
    numberOfStudents: { type: 'string' }
    educationLevel: {
      type: 'array'
      items: { type: 'string' }
    }
    notes: { type: 'string' }
}

module.exports = class RequestQuoteView extends RootView
  id: 'request-quote-view'
  template: require 'templates/request-quote-view'
  
  events:
    'submit form': 'onSubmitForm'
    'click #login-btn': 'onClickLoginButton'
    'click #signup-btn': 'onClickSignupButton'
    
  initialize: ->
    @trialRequest = new TrialRequest({
      properties: {
        email: 'test@gmail.com'
        name: 'Tester'
        organization: 'Test School'
      }
    })
    
  onSubmitForm: (e) ->
    e.preventDefault()
    form = @$('form')
    attrs = forms.formToObject(form)
    if @$('#other-education-level-checkbox').is(':checked')
      attrs.educationLevel.push(@$('#other-education-level-input').val())
    forms.clearFormAlerts(form)
    result = tv4.validateMultiple(attrs, formSchema)
    if not result.valid
      return forms.applyErrorsToForm(form, result.errors)
    if not /^.+@.+\..+$/.test(attrs.email)
      return forms.setErrorToProperty(form, 'email', 'Invalid email.')
    @trialRequest = new TrialRequest({
      type: 'course'
      properties: attrs
    })
    @$('#submit-request-btn').text('Sending').attr('disabled', true)
    @trialRequest.save()
    @trialRequest.on 'sync', @onTrialRequestSubmit, @
    @trialRequest.on 'error', @onTrialRequestError, @

  onTrialRequestError: ->
    @$('#submit-request-btn').text('Submit').attr('disabled', false)

  onTrialRequestSubmit: ->
    @$('form, #form-submit-success').toggleClass('hide')

  onClickLoginButton: ->
    modal = new AuthModal({
      mode: 'login'
      initialValues: { email: @trialRequest.get('properties').email }
    })
    @openModalView(modal)
    window.nextURL = '/courses/teachers'
    
  onClickSignupButton: ->
    props = @trialRequest.get('properties')
    me.set('name', props.name)
    modal = new AuthModal({
      mode: 'signup'
      initialValues: { 
        email: props.email
        schoolName: props.organization
      }
    })
    @openModalView(modal)
    window.nextURL = '/courses/teachers'
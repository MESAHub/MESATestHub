# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/
$ ->
  $('#version_select').parent().parent().removeClass('form-inline')
  $('#version_select').change(->
    this.form.submit()
  )
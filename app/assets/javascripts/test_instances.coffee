# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/
$ ->
  $('.initially-hidden').hide()
  $('#instructions-toggle').click( ->
    $('#instructions-body').removeClass('hidden')
    $('#instructions-body').fadeToggle()
    $('#instructions-toggle').fadeOut( ->
      $('#instructions-toggle').toggleClass('fa-chevron-down')
      $('#instructions-toggle').toggleClass('fa-chevron-right')
      $('#instructions-toggle').fadeIn()      
    )
  )
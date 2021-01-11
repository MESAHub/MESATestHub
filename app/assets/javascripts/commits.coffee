# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/

# $ ->
#   $('.branch-option').click (event) =>
#     selected = $('#selected-branch').text()
#     newBranch = $(event.target).text()
#     $('#selected-branch').html(newBranch)
#     if selected != newBranch
#       alert('making ' + selected + ' invisible')
#       $('#' + selected + '-commits').addClass('d-none')
#       alert('making ' + newBranch + ' visible')
#       $('#' + newBranch + '-commits').removeClass('d-none')

TogglePassing = 
  show_passing: false
  setup: ->
    TogglePassing.show_passing = (getCookie('show-passing') == 'true')

    # if page loads with the show-passing cookie set to true, show passing and
    # adjust text on the button
    if TogglePassing.show_passing
      $('#passing').collapse('show')
      $('span#passing-action').text('Hide')

    # set up listener for clicking on the button to change cookie value
    $('button#toggle-passing').click ->
      setCookie('show-passing', !TogglePassing.show_passing, 7)
      TogglePassing.show_passing = (getCookie('show-passing') == "true")

      # adjust text (showing-hiding handled by bootstrap collapse plugin)
      if TogglePassing.show_passing
        $('span#passing-action').text('Hide')
      else
        $('span#passing-action').text('Show')

      # set up listener so that after passing test cases are displayed, we
      # scroll down to them. Hide in this outer listener so that this doesn't
      # fire on page load.
      $('#passing').on 'shown.bs.collapse', ->
        $('html,body').animate({scrollTop: $('#passing').offset().top})
      
ToggleMissing = 
  show_missin: false
  setup: ->
    ToggleMissing.show_missing = (getCookie('show-missing') == 'true')

    # if page loads with the show-missing cookie set to true, show missing and
    # adjust text on the button
    if ToggleMissing.show_missing
      $('#missing').collapse('show')
      $('span#missing-action').text('Hide')

    # set up listener for clicking on the button to change cookie value
    $('button#toggle-missing').click ->
      setCookie('show-missing', !ToggleMissing.show_missing, 7)
      ToggleMissing.show_missing = (getCookie('show-missing') == "true")

      # adjust text (showing-hiding handled by bootstrap collapse plugin)
      if ToggleMissing.show_missing
        $('span#missing-action').text('Hide')
      else
        $('span#missing-action').text('Show')    

      # set up listener so that after missing test cases are displayed, we
      # scroll down to them. Hide in this outer listener so that this doesn't
      # fire on page load.
      $('#missing').on 'shown.bs.collapse', ->
        $('html,body').animate({scrollTop: $('#missing').offset().top})




$ ->
  $('[data-toggle="tooltip"]').tooltip()
  TogglePassing.setup()
  ToggleMissing.setup()
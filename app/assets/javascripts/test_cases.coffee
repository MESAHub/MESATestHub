# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/

index =
  setup: -> index.make_rows_clickable()
  make_rows_clickable: ->
    $(".clickable-row").css('cursor', 'pointer')
    $(".clickable-row").click( -> window.location = $(this).data("href"))

version_select =
  setup: ->
    version_select.change_form_style()
    version_select.listen_for_change()
  change_form_style: ->
    $('#version_select').parent().parent().removeClass('form-inline')
  listen_for_change: -> 
    $('#version_select').change(-> this.form.submit())
    $('#test_case_select').change(-> this.form.submit())

history_form = 
  setup : ->
    history_form.adjust_computer_select()
  adjust_computer_select: ->
    $('#history_type_show_summaries').click ->
      $('#computers').prop("disabled", true)
      $('.summary').prop("disabled", false)
    $('#history_type_show_instances').click ->
      $('#computers').prop("disabled", false)
      $('.summary').prop("disabled", true)

$ ->
  index.setup()
  version_select.setup()
  history_form.setup()

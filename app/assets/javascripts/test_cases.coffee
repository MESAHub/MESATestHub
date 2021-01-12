# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/

test_case_select = 
  setup: ->
    test_case_select.search_field()
  search_field: ->
    $('#test-case-select').click( ->
      $('#tc-search').focus()
    )
    $('#tc-search').on('input', ->
      self = $(this)
      $('.tc-option').each( ->
        opt = $(this)
        if opt.text().includes(self.val())
          opt.removeClass('d-none')
        else
          opt.addClass('d-none')
      )
    )

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
  history_form.setup()
  test_case_select.setup()

column_control =
  setup: ->
    column_control.column_listener()
  column_listener: ->
    $('.column-switch').change ->
      self = this
      klass = '.column-' + $(self).val()
      if self.checked
        $(klass).removeClass('d-none')
      else
        $(klass).addClass('d-none')
      column_control.adjust_header_widths($(self).data('inlist'))
  adjust_header_widths: (inlist) ->
    header = $('#header-' + inlist)
    header_count = $('.header-column-' + inlist).length - $('.header-column-' + inlist + '.d-none').length
    header.attr('colspan', header_count)
    if header_count > 0
      header.removeClass('d-none')
    else
      header.addClass('d-none')
    

$ ->
  column_control.setup()

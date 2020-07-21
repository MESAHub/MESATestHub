column_control =
  setup: ->
    column_control.column_listener()
    column_control.inlist_listener()
    column_control.date_listener()
  date_listener: ->
    $('#start_date').change ->
      new_val = $(this).val()
      setCookie('commit_start', String(new_val), 7)
    $('#end_date').change ->
      new_val = $(this).val()
      setCookie('commit_end', String(new_val), 7)

  column_listener: ->
    $('.column-switch').change ->
      self = this
      klass = '.column-' + $(self).val()
      if self.checked
        console.log('turned on column ' + klass)
        $(klass).removeClass('d-none')
        setCookie(klass.replace('.', ''), 'checked', 7)
      else
        console.log('turned off column ' + klass)
        $(klass).addClass('d-none')
        setCookie(klass.replace('.', ''), 'unchecked', 7)
      column_control.adjust_header_widths($(self).data('inlist'))
  inlist_listener: ->
    $('.inlist-switch').change ->
      self = $(this)

      # determine inlist from big check box; will use this to select all
      # sub-checkboxes
      inlist = $(self).data('inlist').replace('.', 'p')

      # get all column-associated check boxes
      column_checks = $('.column-switch*[data-inlist="' + inlist + '"]')

      # check them all
      column_checks.prop('checked', $(self).is(':checked'))

      # annoyingly, this doesn't trigger the column listener, so we have to
      # do that manually
      column_checks.each ->
        col = $(this)
        klass = '.column-' + $(col).val()
        if $(self).is(':checked')
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

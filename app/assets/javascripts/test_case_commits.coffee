$ ->
  $('.column-switch').change ->
    self = this
    klass = '.column-' + $(self).val()
    if self.checked
      $(klass).removeClass('d-none')
    else
      $(klass).addClass('d-none')

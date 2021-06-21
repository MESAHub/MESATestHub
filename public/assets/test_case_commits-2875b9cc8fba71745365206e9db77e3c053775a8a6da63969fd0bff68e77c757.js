(function() {
  var column_control;

  column_control = {
    setup: function() {
      column_control.column_listener();
      column_control.inlist_listener();
      return column_control.date_listener();
    },
    date_listener: function() {
      $('#start_date').change(function() {
        var new_val;
        new_val = $(this).val();
        return setCookie('commit_start', String(new_val), 7);
      });
      return $('#end_date').change(function() {
        var new_val;
        new_val = $(this).val();
        return setCookie('commit_end', String(new_val), 7);
      });
    },
    column_listener: function() {
      return $('.column-switch').change(function() {
        var klass, self;
        self = this;
        klass = '.column-' + $(self).val();
        if (self.checked) {
          $(klass).removeClass('d-none');
          setCookie(klass.replace('.', ''), 'checked', 7);
        } else {
          $(klass).addClass('d-none');
          setCookie(klass.replace('.', ''), 'unchecked', 7);
        }
        return column_control.adjust_header_widths($(self).data('inlist'));
      });
    },
    inlist_listener: function() {
      return $('.inlist-switch').change(function() {
        var column_checks, inlist, self;
        self = $(this);
        inlist = $(self).data('inlist').replace('.', 'p');
        column_checks = $('.column-switch*[data-inlist="' + inlist + '"]');
        column_checks.prop('checked', $(self).is(':checked'));
        return column_checks.each(function() {
          var col, klass;
          col = $(this);
          klass = '.column-' + $(col).val();
          if ($(self).is(':checked')) {
            $(klass).removeClass('d-none');
          } else {
            $(klass).addClass('d-none');
          }
          return column_control.adjust_header_widths($(self).data('inlist'));
        });
      });
    },
    adjust_header_widths: function(inlist) {
      var header, header_count;
      header = $('#header-' + inlist);
      header_count = $('.header-column-' + inlist).length - $('.header-column-' + inlist + '.d-none').length;
      header.attr('colspan', header_count);
      if (header_count > 0) {
        return header.removeClass('d-none');
      } else {
        return header.addClass('d-none');
      }
    }
  };

  $(function() {
    return column_control.setup();
  });

}).call(this);

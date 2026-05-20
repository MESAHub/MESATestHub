var column_control = {
  setup: function () {
    column_control.column_listener();
    column_control.inlist_listener();
    column_control.date_listener();
  },

  date_listener: function () {
    $('#start_date').change(function () {
      var new_val = $(this).val();
      setCookie('commit_start', String(new_val), 7);
    });
    $('#end_date').change(function () {
      var new_val = $(this).val();
      setCookie('commit_end', String(new_val), 7);
    });
  },

  column_listener: function () {
    $('.column-switch').change(function () {
      var self = this;
      var klass = '.column-' + $(self).val();
      if (self.checked) {
        $(klass).removeClass('d-none');
        setCookie(klass.replace('.', ''), 'checked', 7);
      } else {
        $(klass).addClass('d-none');
        setCookie(klass.replace('.', ''), 'unchecked', 7);
      }
      column_control.adjust_header_widths($(self).data('inlist'));
    });
  },

  inlist_listener: function () {
    $('.inlist-switch').change(function () {
      var self = $(this);

      // determine inlist from big check box; will use this to select all
      // sub-checkboxes
      var inlist = $(self).data('inlist').replace('.', 'p');

      // get all column-associated check boxes
      var column_checks = $('.column-switch*[data-inlist="' + inlist + '"]');

      // check them all
      column_checks.prop('checked', $(self).is(':checked'));

      // annoyingly, this doesn't trigger the column listener, so we have to
      // do that manually
      column_checks.each(function () {
        var col = $(this);
        var klass = '.column-' + $(col).val();
        if ($(self).is(':checked')) {
          $(klass).removeClass('d-none');
        } else {
          $(klass).addClass('d-none');
        }
        column_control.adjust_header_widths($(self).data('inlist'));
      });
    });
  },

  adjust_header_widths: function (inlist) {
    var header = $('#header-' + inlist);
    var header_count =
      $('.header-column-' + inlist).length -
      $('.header-column-' + inlist + '.d-none').length;
    header.attr('colspan', header_count);
    if (header_count > 0) {
      header.removeClass('d-none');
    } else {
      header.addClass('d-none');
    }
  }
};

var TestLogs = {
  setup: function () {
    if ($('.test-log-link').length) {
      $('.test-log-link').each(function () {
        var anchor = $(this);
        $.ajax({
          url: anchor.attr('href'),
          method: 'HEAD',
          crossDomain: true,
          success: function (returned_data) {
            anchor.hide();
            anchor.removeClass('d-none');
            anchor.fadeIn();
          }
        });
      });
    }
  }
};

$(function () {
  column_control.setup();
  TestLogs.setup();
});

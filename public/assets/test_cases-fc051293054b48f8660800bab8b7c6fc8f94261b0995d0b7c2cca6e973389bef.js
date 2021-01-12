(function() {
  var history_form, test_case_select;

  test_case_select = {
    setup: function() {
      return test_case_select.search_field();
    },
    search_field: function() {
      $('#test-case-select').click(function() {
        return $('#tc-search').focus();
      });
      return $('#tc-search').on('input', function() {
        var self;
        self = $(this);
        return $('.tc-option').each(function() {
          var opt;
          opt = $(this);
          if (opt.text().includes(self.val())) {
            return opt.removeClass('d-none');
          } else {
            return opt.addClass('d-none');
          }
        });
      });
    }
  };

  history_form = {
    setup: function() {
      return history_form.adjust_computer_select();
    },
    adjust_computer_select: function() {
      $('#history_type_show_summaries').click(function() {
        $('#computers').prop("disabled", true);
        return $('.summary').prop("disabled", false);
      });
      return $('#history_type_show_instances').click(function() {
        $('#computers').prop("disabled", false);
        return $('.summary').prop("disabled", true);
      });
    }
  };

  $(function() {
    history_form.setup();
    return test_case_select.setup();
  });

}).call(this);

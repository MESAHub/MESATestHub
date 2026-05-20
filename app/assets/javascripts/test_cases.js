var test_case_select = {
  setup: function () {
    test_case_select.search_field();
  },
  search_field: function () {
    $('#test-case-select').click(function () {
      $('#tc-search').focus();
    });
    $('#tc-search').on('input', function () {
      var self = $(this);
      $('.tc-option').each(function () {
        var opt = $(this);
        if (opt.text().includes(self.val())) {
          opt.removeClass('d-none');
        } else {
          opt.addClass('d-none');
        }
      });
    });
  }
};

var history_form = {
  setup: function () {
    history_form.adjust_computer_select();
  },
  adjust_computer_select: function () {
    $('#history_type_show_summaries').click(function () {
      $('#computers').prop('disabled', true);
      $('.summary').prop('disabled', false);
    });
    $('#history_type_show_instances').click(function () {
      $('#computers').prop('disabled', false);
      $('.summary').prop('disabled', true);
    });
  }
};

$(function () {
  history_form.setup();
  test_case_select.setup();
});

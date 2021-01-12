(function() {
  var ToggleMissing, TogglePassing;

  TogglePassing = {
    show_passing: false,
    setup: function() {
      TogglePassing.show_passing = getCookie('show-passing') === 'true';
      if (TogglePassing.show_passing) {
        $('#passing').collapse('show');
        $('span#passing-action').text('Hide');
      }
      return $('button#toggle-passing').click(function() {
        setCookie('show-passing', !TogglePassing.show_passing, 7);
        TogglePassing.show_passing = getCookie('show-passing') === "true";
        if (TogglePassing.show_passing) {
          $('span#passing-action').text('Hide');
        } else {
          $('span#passing-action').text('Show');
        }
        return $('#passing').on('shown.bs.collapse', function() {
          return $('html,body').animate({
            scrollTop: $('#passing').offset().top
          });
        });
      });
    }
  };

  ToggleMissing = {
    show_missin: false,
    setup: function() {
      ToggleMissing.show_missing = getCookie('show-missing') === 'true';
      if (ToggleMissing.show_missing) {
        $('#missing').collapse('show');
        $('span#missing-action').text('Hide');
      }
      return $('button#toggle-missing').click(function() {
        setCookie('show-missing', !ToggleMissing.show_missing, 7);
        ToggleMissing.show_missing = getCookie('show-missing') === "true";
        if (ToggleMissing.show_missing) {
          $('span#missing-action').text('Hide');
        } else {
          $('span#missing-action').text('Show');
        }
        return $('#missing').on('shown.bs.collapse', function() {
          return $('html,body').animate({
            scrollTop: $('#missing').offset().top
          });
        });
      });
    }
  };

  $(function() {
    $('[data-toggle="tooltip"]').tooltip();
    TogglePassing.setup();
    return ToggleMissing.setup();
  });

}).call(this);

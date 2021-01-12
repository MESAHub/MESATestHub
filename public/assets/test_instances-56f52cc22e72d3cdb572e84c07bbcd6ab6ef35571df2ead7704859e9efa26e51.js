(function() {
  $(function() {
    $('.initially-hidden').hide();
    return $('#instructions-toggle').click(function() {
      $('#instructions-body').removeClass('hidden');
      $('#instructions-body').fadeToggle();
      return $('#instructions-toggle').fadeOut(function() {
        $('#instructions-toggle').toggleClass('fa-chevron-down');
        $('#instructions-toggle').toggleClass('fa-chevron-right');
        return $('#instructions-toggle').fadeIn();
      });
    });
  });

}).call(this);

$(function () {
  $('.initially-hidden').hide();
  $('#instructions-toggle').click(function () {
    $('#instructions-body').removeClass('hidden');
    $('#instructions-body').fadeToggle();
    $('#instructions-toggle').fadeOut(function () {
      $('#instructions-toggle').toggleClass('fa-chevron-down');
      $('#instructions-toggle').toggleClass('fa-chevron-right');
      $('#instructions-toggle').fadeIn();
    });
  });
});

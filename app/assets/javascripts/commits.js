var TogglePassing = {
  show_passing: false,
  setup: function () {
    TogglePassing.show_passing = (getCookie('show-passing') === 'true');

    // if page loads with the show-passing cookie set to true, show passing
    // and adjust text on the button
    if (TogglePassing.show_passing) {
      $('#passing').collapse('show');
      $('span#passing-action').text('Hide');
    }

    // set up listener for clicking on the button to change cookie value
    $('button#toggle-passing').click(function () {
      setCookie('show-passing', !TogglePassing.show_passing, 7);
      TogglePassing.show_passing = (getCookie('show-passing') === 'true');

      // adjust text (showing-hiding handled by bootstrap collapse plugin)
      if (TogglePassing.show_passing) {
        $('span#passing-action').text('Hide');
      } else {
        $('span#passing-action').text('Show');
      }

      // set up listener so that after passing test cases are displayed, we
      // scroll down to them. Hide in this outer listener so that this doesn't
      // fire on page load.
      $('#passing').on('shown.bs.collapse', function () {
        $('html,body').animate({ scrollTop: $('#passing').offset().top });
      });
    });
  }
};

var ToggleMissing = {
  show_missing: false,
  setup: function () {
    ToggleMissing.show_missing = (getCookie('show-missing') === 'true');

    // if page loads with the show-missing cookie set to true, show missing
    // and adjust text on the button
    if (ToggleMissing.show_missing) {
      $('#missing').collapse('show');
      $('span#missing-action').text('Hide');
    }

    // set up listener for clicking on the button to change cookie value
    $('button#toggle-missing').click(function () {
      setCookie('show-missing', !ToggleMissing.show_missing, 7);
      ToggleMissing.show_missing = (getCookie('show-missing') === 'true');

      // adjust text (showing-hiding handled by bootstrap collapse plugin)
      if (ToggleMissing.show_missing) {
        $('span#missing-action').text('Hide');
      } else {
        $('span#missing-action').text('Show');
      }

      // set up listener so that after missing test cases are displayed, we
      // scroll down to them. Hide in this outer listener so that this doesn't
      // fire on page load.
      $('#missing').on('shown.bs.collapse', function () {
        $('html,body').animate({ scrollTop: $('#missing').offset().top });
      });
    });
  }
};

var NearbyCommits = {
  commits: [],
  commit_sha: '',
  branch: '',

  retrieve_commits: function () {
    $.get({
      url: '/commits/nearby_commits.json',
      contentType: 'application/json',
      dataType: 'json',
      data: { branch: NearbyCommits.branch, sha: NearbyCommits.commit_sha },
      success: function (returned_data) {
        NearbyCommits.commits = returned_data.commits;
        if (NearbyCommits.commits && NearbyCommits.commits.length > 0) {
          NearbyCommits.add_commits();
        }
      }
    });
  },

  add_commits: function () {
    $("<ul class='list-group list-group-flush' id='commits'></ul>")
      .appendTo('#nearby-commit-list');
    NearbyCommits.add_commit_list(NearbyCommits.commits, '#commits');

    // deal with previous and next buttons
    var shas = NearbyCommits.commits.map(function (commit) {
      return commit.short_sha;
    });
    var loc = shas.indexOf(NearbyCommits.commit_sha);
    if (loc > 0) {
      var next_commit = NearbyCommits.commits[loc - 1];
      $([
        "<a class='btn btn-outline-primary btn-lg btn-block' href='" + next_commit.url + "'>",
        "  <i class='fa fa-step-forward text-reset'></i>",
        "</a>"
      ].join("\n")).hide().appendTo('#next-btn').fadeIn(200);
    }
    if (loc < (shas.length - 1)) {
      var prev_commit = NearbyCommits.commits[loc + 1];
      $([
        "<a class='btn btn-outline-primary btn-lg btn-block' href='" + prev_commit.url + "'>",
        "  <i class='fa fa-step-backward text-reset'></i>",
        "</a>"
      ].join("\n")).hide().appendTo('#prev-btn').fadeIn(200);
    }
  },

  add_commit_list: function (commit_list, html_list) {
    commit_list.forEach(function (commit) {
      var bonus_cls = '';
      var btn_cls = '';
      var bonus_symbols = '';
      if (commit.short_sha === $('#nearby-commit-center').text()) {
        bonus_cls = 'active';
        btn_cls = 'btn-secondary';
      } else if (commit.status === 3) {
        bonus_cls = 'list-group-item-warning';
        btn_cls = 'btn-warning';
      } else if (commit.status === 2) {
        bonus_cls = 'list-group-item-primary';
        btn_cls = 'btn-primary';
      } else if (commit.status === 1) {
        bonus_cls = 'list-group-item-danger';
        btn_cls = 'btn-danger';
      } else if (commit.status === 0) {
        bonus_cls = 'list-group-item-success';
        btn_cls = 'btn-success';
      } else {
        bonus_cls = 'list-group-item-info';
        btn_cls = 'btn-info';
      }

      if (commit.run_optional) {
        bonus_symbols = bonus_symbols + '<i title="Run Optional" class="fa fa-plus-square"></i>';
      }
      if (commit.fpe_checks) {
        bonus_symbols = bonus_symbols + '<i title="FPE Checks" class="fa fa-wrench"></i>';
      }
      if (commit.fine_resolution) {
        bonus_symbols = bonus_symbols + '<i title="Finer resolution" class="fa fa-search-plus"></i>';
      }

      $([
        "<li class='list-group-item list-group-item-action dropdown-item " + bonus_cls + "''>",
        "  <div class='d-flex w-100 justify-content-between'>",
        "    <h5 class='font-weight-bold d-non d-md-inline'>" + bonus_symbols + commit.message_first_line + "</h5>",
        "    <a class='stretched-link text-reset' href='" + commit.url + "'>",
        "      <button class='btn ml-2 " + btn_cls + "'>",
        "        <span class='h5 text-monospace'>" + commit.short_sha + "</span>",
        "      </button>",
        "    </a>",
        "  </div>",
        "  <div class='d-flex w-100'>",
        "    <p class='mb-0'>",
        "      <span class='font-weight-bold'>" + commit.author + "</span>",
        "      <span>committed on " + commit.commit_time + "",
        "    </p>",
        "  </div>",
        "</li>"
      ].join("\n")).appendTo(html_list);
    });
  },

  setup: function () {
    if ($('#nearby-commit-center').length) {
      NearbyCommits.branch = $('#selected-branch').html();
      NearbyCommits.commit_sha = $('#nearby-commit-center').html();
      NearbyCommits.retrieve_commits();
    }
  }
};

var CommitMessage = {
  setup: function () {
    if ($('#commit-stats').length && $('#commit-message').length) {
      var stats_height = $('#commit-stats').height();
      var message_height = $('#commit-message').height();
      if (message_height > 2.0 * stats_height) {
        $('#commit-message').height(2.0 * stats_height);
      }
    }
  }
};

var BuildLog = {
  setup: function () {
    if ($('.build-log-link').length) {
      $('.build-log-link').each(function () {
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
  $('[data-toggle="tooltip"]').tooltip();
  TogglePassing.setup();
  ToggleMissing.setup();
  NearbyCommits.setup();
  CommitMessage.setup();
  BuildLog.setup();
});

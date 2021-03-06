(function() {
  var BuildLog, CommitMessage, NearbyCommits, ToggleMissing, TogglePassing;

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
    show_missing: false,
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

  NearbyCommits = {
    commits: [],
    commit_sha: '',
    branch: '',
    retrieve_commits: function() {
      return $.get({
        url: 'https://testhub.mesastar.org/commits/nearby_commits.json',
        contentType: 'application/json',
        headers: {
          'Access-Control-Allow-Origin': '*'
        },
        crossDomain: true,
        dataType: 'json',
        data: {
          branch: NearbyCommits.branch,
          sha: NearbyCommits.commit_sha
        },
        success: function(returned_data) {
          NearbyCommits.commits = returned_data.commits;
          if (NearbyCommits.commits && NearbyCommits.commits.length > 0) {
            return NearbyCommits.add_commits();
          }
        }
      });
    },
    add_commits: function() {
      var commit, loc, next_commit, prev_commit, shas;
      $("<ul class='list-group list-group-flush' id='commits'></ul>").appendTo('#nearby-commit-list');
      NearbyCommits.add_commit_list(NearbyCommits.commits, '#commits');
      shas = (function() {
        var i, len, ref, results;
        ref = NearbyCommits.commits;
        results = [];
        for (i = 0, len = ref.length; i < len; i++) {
          commit = ref[i];
          results.push(commit.short_sha);
        }
        return results;
      })();
      loc = shas.indexOf(NearbyCommits.commit_sha);
      if (loc > 0) {
        next_commit = NearbyCommits.commits[loc - 1];
        $(["<a class='btn btn-outline-primary btn-lg btn-block' href='" + next_commit.url + "'>", "  <i class='fa fa-step-forward text-reset'></i>", "</a>"].join("\n")).hide().appendTo('#next-btn').fadeIn(200);
      }
      if (loc < (shas.length - 1)) {
        prev_commit = NearbyCommits.commits[loc + 1];
        return $(["<a class='btn btn-outline-primary btn-lg btn-block' href='" + prev_commit.url + "'>", "  <i class='fa fa-step-backward text-reset'></i>", "</a>"].join("\n")).hide().appendTo('#prev-btn').fadeIn(200);
      }
    },
    add_commit_list: function(commit_list, html_list) {
      var commit, i, len, results;
      results = [];
      for (i = 0, len = commit_list.length; i < len; i++) {
        commit = commit_list[i];
        results.push((function(commit) {
          var bonus_cls, btn_cls;
          bonus_cls = '';
          btn_cls = '';
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
          return $(["<li class='list-group-item list-group-item-action dropdown-item " + bonus_cls + "''>", "  <div class='d-flex w-100 justify-content-between'>", "    <h5 class='font-weight-bold d-non d-md-inline'>" + commit.message_first_line + "</h5>", "    <a class='stretched-link text-reset' href='" + commit.url + "'>", "      <button class='btn ml-2 " + btn_cls + "'>", "        <span class='h5 text-monospace'>" + commit.short_sha + "</span>", "      </button>", "    </a>", "  </div>", "  <div class='d-flex w-100'>", "    <p class='mb-0'>", "      <span class='font-weight-bold'>" + commit.author + "</span>", "      <span>committed on " + commit.commit_time, "    </p>", "  </div>", "</li>"].join("\n")).appendTo(html_list);
        })(commit));
      }
      return results;
    },
    setup: function() {
      if ($('#nearby-commit-center').length) {
        NearbyCommits.branch = $('#selected-branch').html();
        NearbyCommits.commit_sha = $('#nearby-commit-center').html();
        return NearbyCommits.retrieve_commits();
      }
    }
  };

  CommitMessage = {
    setup: function() {
      var message_height, stats_height;
      if ($('#commit-stats').length && $('#commit-message').length) {
        stats_height = $('#commit-stats').height();
        message_height = $('#commit-message').height();
        if (message_height > 2.0 * stats_height) {
          return $('#commit-message').height(2.0 * stats_height);
        }
      }
    }
  };

  BuildLog = {
    setup: function() {
      console.log('in setup');
      if ($('.build-log-link').length) {
        return $('.build-log-link').each(function() {
          var anchor;
          anchor = $(this);
          return $.ajax({
            url: anchor.attr('href'),
            method: 'HEAD',
            headers: {
              'Access-Control-Allow-Origin': '*'
            },
            crossDomain: true,
            success: function(returned_data) {
              return anchor.fadeIn();
            }
          });
        });
      }
    }
  };

  $(function() {
    $('[data-toggle="tooltip"]').tooltip();
    TogglePassing.setup();
    ToggleMissing.setup();
    NearbyCommits.setup();
    CommitMessage.setup();
    return BuildLog.setup();
  });

}).call(this);

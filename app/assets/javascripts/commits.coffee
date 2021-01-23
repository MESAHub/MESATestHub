# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/

# $ ->
#   $('.branch-option').click (event) =>
#     selected = $('#selected-branch').text()
#     newBranch = $(event.target).text()
#     $('#selected-branch').html(newBranch)
#     if selected != newBranch
#       alert('making ' + selected + ' invisible')
#       $('#' + selected + '-commits').addClass('d-none')
#       alert('making ' + newBranch + ' visible')
#       $('#' + newBranch + '-commits').removeClass('d-none')

TogglePassing = 
  show_passing: false
  setup: ->
    TogglePassing.show_passing = (getCookie('show-passing') == 'true')

    # if page loads with the show-passing cookie set to true, show passing and
    # adjust text on the button
    if TogglePassing.show_passing
      $('#passing').collapse('show')
      $('span#passing-action').text('Hide')

    # set up listener for clicking on the button to change cookie value
    $('button#toggle-passing').click ->
      setCookie('show-passing', !TogglePassing.show_passing, 7)
      TogglePassing.show_passing = (getCookie('show-passing') == "true")

      # adjust text (showing-hiding handled by bootstrap collapse plugin)
      if TogglePassing.show_passing
        $('span#passing-action').text('Hide')
      else
        $('span#passing-action').text('Show')

      # set up listener so that after passing test cases are displayed, we
      # scroll down to them. Hide in this outer listener so that this doesn't
      # fire on page load.
      $('#passing').on 'shown.bs.collapse', ->
        $('html,body').animate({scrollTop: $('#passing').offset().top})
      
ToggleMissing = 
  show_missing: false
  setup: ->
    ToggleMissing.show_missing = (getCookie('show-missing') == 'true')

    # if page loads with the show-missing cookie set to true, show missing and
    # adjust text on the button
    if ToggleMissing.show_missing
      $('#missing').collapse('show')
      $('span#missing-action').text('Hide')

    # set up listener for clicking on the button to change cookie value
    $('button#toggle-missing').click ->
      setCookie('show-missing', !ToggleMissing.show_missing, 7)
      ToggleMissing.show_missing = (getCookie('show-missing') == "true")

      # adjust text (showing-hiding handled by bootstrap collapse plugin)
      if ToggleMissing.show_missing
        $('span#missing-action').text('Hide')
      else
        $('span#missing-action').text('Show')    

      # set up listener so that after missing test cases are displayed, we
      # scroll down to them. Hide in this outer listener so that this doesn't
      # fire on page load.
      $('#missing').on 'shown.bs.collapse', ->
        $('html,body').animate({scrollTop: $('#missing').offset().top})

NearbyCommits = 
  commits: []
  commit_sha: ''
  branch: ''
  retrieve_commits: ->
    # use this for development due to CORS issues
    # $.get({url: 'http://localhost:3000/commits/nearby_commits.json', contentType: 'application/json', dataType: 'json', data: {branch: NearbyCommits.branch, sha: NearbyCommits.commit_sha}, success: (returned_data) ->
    $.get({url: 'https://testhub.mesastar.org/commits/nearby_commits.json', contentType: 'application/json', dataType: 'json', data: {branch: NearbyCommits.branch, sha: NearbyCommits.commit_sha}, success: (returned_data) ->
      NearbyCommits.commits = returned_data.commits
      if NearbyCommits.commits && NearbyCommits.commits.length > 0
        NearbyCommits.add_commits()
    })

  add_commits: ->
    $("<ul class='list-group list-group-flush' id='commits'></ul>").appendTo('#nearby-commit-list')
    NearbyCommits.add_commit_list(NearbyCommits.commits, '#commits')
    # deal with previous and next buttons
    shas = (commit.short_sha for commit in NearbyCommits.commits)
    loc = shas.indexOf(NearbyCommits.commit_sha)
    if loc > 0
      next_commit = NearbyCommits.commits[loc - 1]
      $([
        "<a class='btn btn-outline-primary btn-lg btn-block' href='#{next_commit.url}'>",
        "  <i class='fa fa-step-forward text-reset'></i>",
        "</a>"
      ].join("\n")).hide().appendTo('#next-btn').fadeIn(200)
    if loc < (shas.length - 1)
      prev_commit = NearbyCommits.commits[loc + 1]
      $([
        "<a class='btn btn-outline-primary btn-lg btn-block' href='#{prev_commit.url}'>",
        "  <i class='fa fa-step-backward text-reset'></i>",
        "</a>"
      ].join("\n")).hide().appendTo('#prev-btn').fadeIn(200)

    


  add_commit_list: (commit_list, html_list) ->
    for commit in commit_list
      do (commit) ->
        bonus_cls = ''
        btn_cls = ''
        if commit.short_sha == $('#nearby-commit-center').text()
          bonus_cls = 'active'
          btn_cls = 'btn-secondary'
        else if commit.status == 3
          bonus_cls = 'list-group-item-warning'
          btn_cls = 'btn-warning'
        else if commit.status == 2
          bonus_cls = 'list-group-item-primary'
          btn_cls = 'btn-primary'
        else if commit.status == 1
          bonus_cls = 'list-group-item-danger'
          btn_cls = 'btn-danger'
        else if commit.status == 0
          bonus_cls = 'list-group-item-success'
          btn_cls = 'btn-success'
        else
          bonus_cls = 'list-group-item-info'
          btn_cls = 'btn-info'
          
        $([
          "<li class='list-group-item list-group-item-action dropdown-item #{bonus_cls}''>",
          "  <div class='d-flex w-100 justify-content-between'>",
          "    <h5 class='font-weight-bold d-non d-md-inline'>#{commit.message_first_line}</h5>",
          "    <a class='stretched-link text-reset' href='#{commit.url}'>",
          "      <button class='btn ml-2 #{btn_cls}'>",
          "        <span class='h5 text-monospace'>#{commit.short_sha}</span>",
          "      </button>",
          "    </a>",
          "  </div>",
          "  <div class='d-flex w-100'>",
          "    <p class='mb-0'>",
          "      <span class='font-weight-bold'>#{commit.author}</span>",
          "      <span>committed on #{commit.commit_time}",
          "    </p>",
          "  </div>",
          "</li>"
        ].join("\n")).appendTo(html_list)

  setup: ->
    if $('#nearby-commit-center').length
      NearbyCommits.branch = $('#selected-branch').html()
      NearbyCommits.commit_sha = $('#nearby-commit-center').html()
      NearbyCommits.retrieve_commits()

$ ->
  $('[data-toggle="tooltip"]').tooltip()
  TogglePassing.setup()
  ToggleMissing.setup()
  NearbyCommits.setup()
  
# Parse CI directive flags out of the first line of a MESA commit
# message.
#
# Returns a hash mirroring the four boolean columns on `commits`:
#
#   {
#     ci_skip:            Boolean,
#     wants_full_inlists: Boolean,
#     wants_fpe:          Boolean,
#     wants_converge:     Boolean
#   }
#
# Only the first line is scanned. Squash and merge commits routinely
# list every constituent commit's subject in their body, which would
# otherwise pull every `[ci ...]` directive from every squashed
# commit into the merge — leading to a single landed PR claiming
# `[ci skip]` AND `[ci fpe]` AND `[ci optional]` because some PR
# branch commit mentioned each of them. The MESA convention is to
# place directives in the subject line of the actual commit they
# apply to.
#
# `[ci skip]` is suppressed when the same line also requests
# `[ci optional]` or `[ci fpe]` — this catches the edge case of a
# subject like `Merge X [ci skip] [ci optional]` where the
# directives contradict. `[ci converge]` is not part of that
# suppression set, matching the existing legacy behavior in
# app/models/commit.rb.
#
# Hooked into the ingest path via `Commit.hash_from_github`, which
# is the single chokepoint feeding both `insert_all` (bulk webhook
# sync) and `create_or_update_from_github_hash` (one-off fetches).
module CommitMessageFlags
  SKIP_RE           = /\[\s*ci\s+skip\s*\]/.freeze
  FULL_INLISTS_RE   = /\[\s*ci\s+optional(\s+\d+)?\s*\]/.freeze
  FPE_RE            = /\[\s*ci\s+fpe\s*\]/.freeze
  CONVERGE_RE       = /\[\s*ci\s+converge\s*\]/.freeze

  def self.parse(message)
    # `String#lines.first` returns the leading line *with* its
    # trailing newline; `to_s` collapses the nil result from an
    # empty/nil message to "". Trailing whitespace doesn't affect
    # any of the four regexes, so no chomp needed.
    first_line = message.to_s.lines.first.to_s

    wants_full_inlists = !!(first_line =~ FULL_INLISTS_RE)
    wants_fpe          = !!(first_line =~ FPE_RE)
    wants_converge     = !!(first_line =~ CONVERGE_RE)
    ci_skip            = !!(first_line =~ SKIP_RE) &&
                         !(wants_full_inlists || wants_fpe)

    {
      ci_skip: ci_skip,
      wants_full_inlists: wants_full_inlists,
      wants_fpe: wants_fpe,
      wants_converge: wants_converge
    }
  end
end

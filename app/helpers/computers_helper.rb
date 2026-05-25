module ComputersHelper
  # Ordered list of [sort_key, dropdown_label] pairs for the
  # `computers#index` Sort dropdown. The admin all-users view
  # exposes the maintainer ordering; the per-user view drops it
  # since there's only one maintainer. Order in the array is the
  # order rendered in the menu — most-useful default first.
  def computer_sort_options(include_maintainer:)
    opts = [
      ["recent", "Most recent activity"],
      ["name",   "Computer name (A→Z)"]
    ]
    opts.insert(1, ["maintainer", "Maintainer (A→Z)"]) if include_maintainer
    opts
  end

  def computer_sort_label(sort)
    computer_sort_options(include_maintainer: true)
      .find { |key, _| key == sort.to_s }&.last || "Most recent activity"
  end
end

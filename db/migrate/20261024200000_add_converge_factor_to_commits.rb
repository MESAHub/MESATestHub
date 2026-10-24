# `[ci converge 0.5]` asks for convergence runs at a specific
# MESA_TEST_SUITE_RESOLUTION_FACTOR (docs/dispatcher-and-claims.md,
# "Converge factor"). Null for a bare `[ci converge]`, where the client's
# default (0.8) applies.
class AddConvergeFactorToCommits < ActiveRecord::Migration[8.0]
  def change
    add_column :commits, :converge_factor, :float
  end
end

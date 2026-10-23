# What a claimed run is running on (docs/dispatcher-and-claims.md,
# "Claim details"), so a claim that sits around for hours can be read
# at a glance: an old laptop on two threads, a different SDK, etc. All
# optional -- the client sends what it knows (a build claim is made
# before compiling, so it can't know the compiler yet).
class AddEnvironmentToClaims < ActiveRecord::Migration[8.0]
  def change
    add_column :claims, :sdk_version, :string
    add_column :claims, :compiler, :string
    add_column :claims, :compiler_version, :string
    add_column :claims, :math_backend, :string
    add_column :claims, :omp_num_threads, :integer
    add_column :claims, :platform_version, :string
  end
end

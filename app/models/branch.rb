class Branch < ApplicationRecord
  has_one :head, class_name: 'Commit', foreign_key: 'head_id'

  has_many :branch_memberships
  has_many :commits, through: :branch_memberships

  def self.api_branches
    uri = URI("https://api.github.com/repos/MESAHub/mesa-sandbox-lfs/branches")
    https = Net::HTTP.new(uri.host, uri.port)
    https.use_ssl = true

    headers = {
      'Authorization' => "token #{ENV['GIT_TOKEN']}",
      'Accept' => 'application/vnd.github.v3+json',
      'User-Agent' => 'MESATesthub'
    }

    request = Net::HTTP::Get.new(uri.path)
    headers.each_pair do |key, val|
      request[key] = val
    end
    https.request(request).body
  end

end

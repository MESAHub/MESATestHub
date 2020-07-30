class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  ####################
  # GITHUB API STUFF #
  ####################
  @@client = Octokit::Client.new(access_token: ENV['GIT_TOKEN'])
  @@client.auto_paginate = true
  @@repo_path = 'MESAHub/mesa-sandbox-lfs'


  def self.api
    puts '###################'
    puts "making an api call!"
    puts '###################'
    @@client
  end

  def self.repo_path
    @@repo_path
  end

  @@api_root = 'https://api.github.com/repos/MESAHub/mesa-sandbox-lfs/'

  def self.api_raw_call(full_path, **params)
    uri = URI(full_path)
    unless params.empty?
      uri.query = URI.encode_www_form(params)
    end
    https = Net::HTTP.new(uri.host, uri.port)
    https.use_ssl = true

    headers = {
      'Authorization' => "token #{ENV['GIT_TOKEN']}",
      'Accept' => 'application/vnd.github.v3+json',
      'User-Agent' => 'MESATesthub'
    }

    request = Net::HTTP::Get.new(uri)
    headers.each_pair do |key, val|
      request[key] = val
    end
    https.request(request)
  end

  def self.api_body(sub_path, **params)
    JSON.load(api_raw_call(@@api_root + sub_path, **params).body)
  end

  def self.api_hash(sub_path, **params)
    api_raw_call(@@api_root + sub_path, **params).to_hash
  end

  # iterates through paginated results
  def self.api_concatenate_call(sub_path, **params)
    # in theory, result is an array. We'll build up over multiple api calls
    res = []
    # do first call to determine number of pages
    page_num = 1
    this_params = params.merge({page: page_num})
    page = api_raw_call(@@api_root + sub_path, **this_params)
    res += JSON.load(page.body)
    link_hash = {}
    if page.to_hash['link']
      page.to_hash['link'].each do |link_line|
        if /rel="([^"]+)"/ =~ link_line
          link_hash[$1] = /<(https:\/\/api.github.com\/[^>]+)>/.match(link_line)[1]
        end
      end
      while link_hash['next']
        # rely on links from headers of previous call; don't try to make your own
        # these links include base path, so just do a "raw call" and convert to a
        # hash as needed
        page = api_raw_call(link_hash['next'])
        link_hash = {}
        page.to_hash['link'].each do |link_line|
          if /rel="([^"]+)"/ =~ link_line
            link_hash[$1] = /<(https:\/\/api.github.com\/[^>]+)>/.match(link_line)[1]
          end
        end
        res += JSON.load(page.body)
      end
    end
    res
  end
end

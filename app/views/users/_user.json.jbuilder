json.extract! user, :id, :email, :name, :admin, :time_zone, :created_at,
              :updated_at
json.url user_url(user, format: json)
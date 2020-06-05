json.extract! computer, :id, :name, :platform, :processor, :ram_gb, :created_at, :updated_at
json.user do
  json.partial! 'users/user', user: computer.user
end
json.url computer_url(computer, format: :json)

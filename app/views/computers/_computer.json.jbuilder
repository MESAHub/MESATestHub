json.extract! computer, :id, :name, :platform, :processor, :ram_gb, :created_at, :updated_at
json.user do
  json.partial! 'users/user', user: computer.user
end
json.url user_computer_url(computer, computer.user, format: :json)

json.extract! submission, :id, :compiled, :entire, :empty, :created_at, :updated_at
json.commit do
  json.partial! "commits/commit", commit: @submission.commit
end
json.computer do
  json.partial! "computers/computer", computer: @submission.computer
end
json.url computer_submission_url(computer: @submission.computer.name, id: @submission.id, format: :json)

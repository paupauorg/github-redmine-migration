#encoding: utf-8
require 'rubygems'
gem 'activeresource', '~> 3.2.12'
require 'active_resource'
require 'github_api'
require 'yaml'


config = YAML.load_file('config.yml')
REDMINE_SITE = config['REDMINE_SITE']
REDMINE_TOKEN = config['REDMINE_TOKEN']
ORGANIZATION  = config['ORGANIZATION']
GITHUB_TOKEN = config['GITHUB_TOKEN']

github = Github.new do |config|
  config.endpoint    = 'https://api.github.com'
  config.site        = 'https://api.github.com'
  config.oauth_token = GITHUB_TOKEN
  config.adapter     = :net_http
  config.ssl         = {:verify => false}
  config.auto_pagination    = true
end

class User < ActiveResource::Base
  self.format = :xml
  self.site = REDMINE_SITE
  self.user = REDMINE_TOKEN
  self.password = 'nothing'
end

class IssueStatus < ActiveResource::Base
  self.format = :xml
  self.site = REDMINE_SITE
  self.user = REDMINE_TOKEN
  self.password = 'nothing'
end

class Tracker < ActiveResource::Base
  self.format = :xml
  self.site = REDMINE_SITE
  self.user = REDMINE_TOKEN
  self.password = 'nothing'
end

class IssuePriority < ActiveResource::Base
  self.format = :xml
  self.site = "#{REDMINE_SITE}/enumerations"
  self.user = REDMINE_TOKEN
  self.password = 'nothing'
end

class Role < ActiveResource::Base
  self.format = :xml
  self.site = REDMINE_SITE
  self.user = REDMINE_TOKEN
  self.password = 'nothing'
end

issue_statuses =  IssueStatus.all
priorities = IssuePriority.all
issue_status_names = issue_statuses.collect { |is| is.name }
priority_names = priorities.collect { |p| p.name }
roles = Role.all
role_names = roles.collect { |r| r.name }

trackers = Tracker.all
tracker_names = trackers.collect {|t| t.name }
users = User.all
$user_names = users.collect { |u| u.login }

puts "Name of open issue status - #{issue_status_names}"
open_issue_status_name = gets.chomp

puts "Name of closed issue status - #{issue_status_names}"
closed_issue_status_name = gets.chomp

puts "Name of normal priority - #{priority_names}"
default_priority_name = gets.chomp


puts "Name of default role - #{role_names}"
default_role_name = gets.chomp

puts "Available trackers: #{tracker_names}"
puts "Select tracker:"
tracker_name = gets.chomp

puts "Import images? (true/false)"
import_images = gets.chomp
if import_images.upcase == 'TRUE'
  import_images = true
else
  import_images = false
end

repos =  github.repos.list(org: ORGANIZATION)

$user_mapping = {}

def process_user(login)
  user = nil
  user = $user_mapping[login] if $user_mapping.has_key? login
  if user.nil? || user == ''
    puts "Select mapping of github user #{login}  - 'skip' or blank for no mapping"
    puts "Available users: #{$user_names}"
    e_login = gets.chomp
    $user_mapping[login] = e_login
  end
end

repos.each do |repo|
  issues = github.issues.list(user: ORGANIZATION, repo: repo.name).to_a
  issues = issues | github.issues.list(user: ORGANIZATION, repo: repo.name, state: 'closed').to_a
  issues.each do |is|
    process_user is.user.login
    process_user is.assignee.login unless is.assignee.nil?
    github.issues.events.list(user: ORGANIZATION, repo: repo.name, issue_id: is.number).each do |event|
       if ['closed', 'reopened'].include? event.event
         process_user event.actor.login
       end
    end
    github.issues.comments.list(user: ORGANIZATION, repo: repo.name, issue_id: is.number).each do |comment|
      process_user comment.user.login
    end
  end
end

config = {
    'REDMINE_SITE' => config['REDMINE_SITE'],
    'REDMINE_TOKEN' => config['REDMINE_TOKEN'],
    'ORGANIZATION'  => config['ORGANIZATION'],
    'GITHUB_TOKEN' => config['GITHUB_TOKEN'],
    'OPEN_ISSUE_STATUS_NAME' => open_issue_status_name,
    'CLOSED_ISSUE_STATUS_NAME' => closed_issue_status_name,
    'DEFAULT_PRIORITY_NAME' => default_priority_name,
    'DEFAULT_ROLE' => default_role_name,
    'DEFAULT_TRACKER' => tracker_name,
    'IMPORT_IMAGES' => import_images,
    'USER_MAPPING' => $user_mapping
}

File.open('generate.config.yml', 'w') {|f| f.write(config.to_yaml)}
puts 'Wrote to generate.config.yml'
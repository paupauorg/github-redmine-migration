#encoding: utf-8
require 'rubygems'
gem 'activeresource', '~> 3.2.12'
require 'active_resource'
require 'github_api'

REDMINE_TOKEN = ''
REDMINE_SITE = 'http://0.0.0.0:3000'
GITHUB_TOKEN = ''
ORGANIZATION = 'paupaude'


class Issue < ActiveResource::Base
  self.format = :xml
  self.site = REDMINE_SITE
  self.user = REDMINE_TOKEN
  self.password = 'nothing'

  def impersonate(login)
    #headers['X-Redmine-Switch-User'] = 'tobias'
  end
  def remove_impersonation
    #@headers = { }
  end
end

class Project < ActiveResource::Base
  self.format = :xml
  self.site = REDMINE_SITE
  self.user = REDMINE_TOKEN
  self.password = 'nothing'
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

class Version < ActiveResource::Base
  self.format = :xml
  self.site = "#{REDMINE_SITE}/projects/:project_id"
  self.user = REDMINE_TOKEN
  self.password = 'nothing'
end

class IssueCategory < ActiveResource::Base
  self.format = :xml
  self.site = "#{REDMINE_SITE}/projects/:project_id"
  self.user = REDMINE_TOKEN
  self.password = 'nothing'
end



github = Github.new do |config|
  config.endpoint    = 'https://api.github.com'
  config.site        = 'https://api.github.com'
  config.oauth_token = GITHUB_TOKEN
  config.adapter     = :net_http
  config.ssl         = {:verify => false}
end

$user_mapping = {}
repos =  github.repos.list(org: ORGANIZATION)
issue_statuses =  IssueStatus.all
puts 'Name of open issue status - (new)'
open_issue_status_name = gets.chomp
open_issue_status_name = 'new' if open_issue_status_name == ''
open_issue_status = issue_statuses.detect { |is| is.name.upcase == open_issue_status_name.upcase}
puts 'Name of closed issue status - (closed)'
closed_issue_status_name = gets.chomp
closed_issue_status_name = 'closed' if closed_issue_status_name == ''
closed_issue_status = issue_statuses.detect { |is| is.name.upcase == closed_issue_status_name.upcase}
puts 'Name of normal priority - (default)'
normal_priority_name = gets.chomp
normal_priority_name = 'normal' if normal_priority_name == ''
normal_priority = IssuePriority.all.detect { |ip| ip.name.upcase == normal_priority_name.upcase }
$redmine_projects = Project.find(:all)
$trackers = Tracker.all
$users = User.all

def find_project(name)
  $redmine_projects.find { |p| p.name.upcase == name.upcase }
end

def find_tracker(name)
  $trackers.find { |t| t.name.upcase == name.upcase }
end

def find_user(login)
  $users.find { |u| u.login.upcase == login.upcase }
end

def get_user_mapping(login)
  $user_mapping[login]
end

def set_user_mapping(redmine, github)
  $user_mapping[github] = find_user(redmine)
end

tracker_names = $trackers.collect { |t| t.name }
user_names = $users.collect { |u| u.login }
project_names = $redmine_projects.collect { |p| p.name }

repos.each do |repo|
  name = repo.name
  puts "Processing Repo #{name}"
  open_issues = github.issues.list(user: ORGANIZATION, repo: name)
  puts "#{open_issues.size} open issues"
  closed_issues = github.issues.list(user: ORGANIZATION, repo: name, state: 'closed')
  puts "#{closed_issues.size} closed issues"
  puts "Enter name of Redmine project - type 'skip' to skip - (#{name})"
  puts "Available projects #{project_names}"
  redmine_project = gets.chomp
  redmine_project = name if redmine_project == ''
  if redmine_project == 'skip'
    puts "Skipping #{name}"
  else
    project = find_project(redmine_project)
    if project.nil?
      puts "creating #{redmine_project} project"
      project = Project.new(name: redmine_project, identifier: redmine_project)
      if project.save
        puts "project saved"
      else
        puts "project error #{project.errors.full_messages}"
        abort("Cannot continue")
      end
    else
      puts "Project exists"
    end
    $redmine_projects = Project.all

    project  = Project.find(project.id, params: {include: 'trackers'})

    puts "Available trackers: #{tracker_names}"
    puts "Select tracker: - (bug)"
    tracker_name = gets.chomp
    tracker_name = 'Bug' if tracker_name == ''
    tracker = find_tracker(tracker_name)
    if !project.trackers.include?(tracker)
      puts "saving tracker"
      project.trackers << tracker
      project.tracker_ids = project.trackers.collect {|t| t.id}
      project.save
    end
    puts "Processing open issues"

    versions = Version.find(:all, :params => {:project_id => project.id})

    open_issues.each do |oi|
      i = Issue.new project_id: project.id, status_id: open_issue_status.id, priority_id: normal_priority.id, subject: oi.title,
                description: oi.body, start_date: Time.parse(oi.created_at).to_date, tracker_id: tracker.id
      if !oi.milestone.nil?
        version = versions.find { |v| v.name.upcase == oi.milestone.title.upcase } unless versions.nil?
        if version.nil?
          version = Version.new name: oi.milestone.title, status: oi.milestone.state, project_id: project.id
          version.effective_date = Date.parse(oi.milestone.due_on).to_s unless oi.milestone.due_on.nil?
          puts version.inspect
          version.save!
          puts "versions saved"
        end
        i.fixed_version_id = version.id
      end

      if !oi.labels.nil? && !oi.labels.empty?
        label = oi.labels[0]
        categs = IssueCategory.find(:all, :params => {:project_id => project.id})
        categ = categs.find { |c| c.name == label.name }
        if categ.nil?
          categ = IssueCategory.new name: label.name, project_id: project.id
          categ.save!
        end
        i.category_id = categ.id
      end
      if !oi.user.nil?
        login = oi.user.login
        user = get_user_mapping(login.upcase)
        if user.nil?
          puts "Select mapping of github user #{login}  - 'skip' or blank for no mapping"
          puts "Available users: #{user_names}"
          e_login = gets.chomp
          set_user_mapping(e_login.upcase, login.upcase)
          user = get_user_mapping(login.upcase)
        end
        i.impersonate(user.login) unless user.nil?
      end
      if !oi.assignee.nil?
        login = oi.assignee.login
        user = get_user_mapping(login.upcase)
        if user.nil?
          puts "Select mapping of github user #{login}  - 'skip' or blank for no mapping"
          puts "Available users: #{user_names}"
          e_login = gets.chomp
          set_user_mapping(e_login.upcase, login.upcase)
          user = get_user_mapping(login.upcase)
        end
        i.assigned_to_id = user.id unless user.nil?
      end
      if i.save!
        puts "issue saved"
      else
        puts "issue error #{i.errors.full_messages}"
      end
      #gets
      i.remove_impersonation
      if oi.comments > 0
        github.issues.comments.list(user: ORGANIZATION, repo: name, issue_id: oi.number).each do |comment|
          i.notes = comment.body
          i.save!
        end
      end
    end

    puts "Processing closed issues"
    closed_issues.each do |ci|
      i = Issue.new project_id: project.id, status_id: closed_issue_status.id, priority_id: normal_priority.id, subject: ci.title,
                    description: ci.body, start_date: Time.parse(ci.created_at).to_date, closed_on: Time.parse(ci.closed_at)
      if !ci.milestone.nil?
        version = versions.find { |v| v.name.upcase == ci.milestone.title.upcase } unless versions.nil?
        if version.nil?
          version = Version.new name: ci.milestone.title, status: ci.milestone.state, project_id: project.id
          version.date = Date.parse(ci.milestone.due_on).to_s unless ci.milestone.due_on.nil?
          version.save!
        end
        i.fixed_version_id = version.id
      end

      if !ci.labels.nil? && !ci.labels.empty?
        label = ci.labels[0]
        categs = IssueCategory.find(:all, :params => {:project_id => project.id})
        categ = categs.find { |c| c.name == label.name }
        if categ.nil?
          categ = IssueCategory.new name: label.name, project_id: project.id
          categ.save!
        end
        i.category_id = categ.id
      end
      if !ci.user.nil?
        login = ci.user.login
        user = get_user_mapping(login.upcase)
        if user.nil?
          puts "Select mapping of github user #{login}  - 'skip' or blank for no mapping"
          puts "Available users: #{user_names}"
          e_login = gets.chomp
          set_user_mapping(e_login.upcase, login.upcase)
          user = get_user_mapping(login.upcase)
        end
        i.author_id = user.id  unless user.nil?
      end
      if !ci.assignee.nil?
        login = ci.assignee.login
        user = get_user_mapping(login.upcase)
        if user.nil?
          puts "Select mapping of github user #{login} - 'skip' or blank for no mapping"
          puts "Available users: #{user_names}"
          e_login = gets.chomp
          set_user_mapping(e_login.upcase, login.upcase)
          user = get_user_mapping(login.upcase)
        end
        i.assigned_to_id = user.id unless user.nil?
      end
      

      if i.save!
        puts "issue saved"
      else
        puts "issue error #{i.errors.full_messages}"
      end

      if ci.comments > 0
        github.issues.comments.list(user: ORGANIZATION, repo: name, issue_id: ci.number).each do |comment|
          i.notes = comment.body
          i.save!
        end
      end
      if i.respond_to? :custom_fields
        i.custom_fields[0].value = Date.parse(ci.closed_at).to_s
        i.save!
      end
    end
  end
end

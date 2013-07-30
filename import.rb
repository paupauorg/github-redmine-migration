#encoding: utf-8
require 'rubygems'
gem 'activeresource', '~> 3.2.12'
require 'active_resource'
require 'github_api'
require_relative 'pandoc-ruby'
require 'yaml'


start_time = Time.now

config = YAML.load_file('config.yml')
REDMINE_SITE = config['REDMINE_SITE']
REDMINE_TOKEN = config['REDMINE_TOKEN']
ORGANIZATION  = config['ORGANIZATION']
GITHUB_TOKEN = config['GITHUB_TOKEN']
REPOSITORY_FILTER = config['REPOSITORY_FILTER'] || []
CLOSE_DATE = config['CLOSE_DATE'] || 'none'
open_issue_status_name = config['OPEN_ISSUE_STATUS_NAME']
closed_issue_status_name = config['CLOSED_ISSUE_STATUS_NAME']
default_priority_name = config['DEFAULT_PRIORITY_NAME']
default_role_name = config['DEFAULT_ROLE']
DEFAULT_TRACKER = config['DEFAULT_TRACKER']

class MyConn < ActiveResource::Connection

  attr_reader :last_resp
  def handle_response(resp)
    @last_resp=resp
    super
  end
end


class Issue < ActiveResource::Base
  class << self
    attr_writer :connection
  end

  self.format = :xml
  self.site = REDMINE_SITE
  self.user = REDMINE_TOKEN
  self.password = 'nothing'

  def impersonate(login = '')
    Issue.headers['X-Redmine-Switch-User'] = login if login != ''
  end

  def remove_impersonation
    Issue.headers['X-Redmine-Switch-User'] = ''
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

class UpdateVersion < ActiveResource::Base
  self.format = :xml
  self.site = REDMINE_SITE
  self.user = REDMINE_TOKEN
  self.password = 'nothing'
  self.element_name = "version"
end

class IssueCategory < ActiveResource::Base
  self.format = :xml
  self.site = "#{REDMINE_SITE}/projects/:project_id"
  self.user = REDMINE_TOKEN
  self.password = 'nothing'
end

class Role < ActiveResource::Base
  self.format = :xml
  self.site = REDMINE_SITE
  self.user = REDMINE_TOKEN
  self.password = 'nothing'
end


class Membership < ActiveResource::Base
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
$project_memberships = {}
repos =  github.repos.list(org: ORGANIZATION)
issue_statuses =  IssueStatus.all
priorities = IssuePriority.all
issue_status_names = issue_statuses.collect { |is| is.name }
priority_names = priorities.collect { |p| p.name }
if open_issue_status_name.nil?
  puts "Name of open issue status - #{issue_status_names}"
  open_issue_status_name = gets.chomp
end
open_issue_status = issue_statuses.detect { |is| is.name.upcase == open_issue_status_name.upcase}

if closed_issue_status_name.nil?
  puts "Name of closed issue status - #{issue_status_names}"
  closed_issue_status_name = gets.chomp
end
closed_issue_status = issue_statuses.detect { |is| is.name.upcase == closed_issue_status_name.upcase}

if default_priority_name.nil?
  puts "Name of normal priority - #{priority_names}"
  default_priority_name = gets.chomp
end

normal_priority = priorities.detect { |ip| ip.name.upcase == default_priority_name.upcase }
roles = Role.all

if default_role_name.nil?
  role_names = roles.collect { |r| r.name }
  puts "Name of default role - #{role_names}"
  default_role_name = gets.chomp
end

$reporter = Role.all.find { |role| role.name.upcase == default_role_name.upcase }

$redmine_projects = Project.find(:all, params: { limit: 100 })
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

def convert_code_blocks(block)
  i = 1
  x = block.gsub('```') do |m|
    i += 1
    i % 2  == 0 ? '<pre><code>' : '</code></pre>'
  end
  x
end


def clean_pandoc(block)
  block.gsub('"$":', '').gsub('!http', '!{width: 50%}http')
end

def find_or_create_user(github_login)
  user = get_user_mapping(github_login.upcase)
  if user.nil?
    puts "Select mapping of github user #{github_login}  - 'skip' or blank for no mapping"
    puts "Available users: #{$user_names}"
    e_login = gets.chomp
    set_user_mapping(e_login.upcase, github_login.upcase)
    user = get_user_mapping(github_login.upcase)
  end
  user
end

def check_or_create_membership(project, user)
  $project_memberships[project.id] = [] unless $project_memberships.has_key? project.id
  member = $project_memberships[project.id].find {|member| member == user.id}
  if member.nil?
    membership = Membership.new(user_id: user.id, role_ids: [$reporter.id], project_id: project.id )
    membership.save!
    $project_memberships[project.id] << user.id
    member = user.id
  end
  return member.nil? ? false : true
end

def add_members_to_project_mapping(project, memberships)
  $project_memberships[project.id] = [] unless $project_memberships.has_key? project.id
  memberships.each { |membership| $project_memberships[project.id] << membership.user.id }
end

tracker_names = $trackers.collect { |t| t.name }
$user_names = $users.collect { |u| u.login }
puts "Only processing #{REPOSITORY_FILTER}" unless REPOSITORY_FILTER.nil? || REPOSITORY_FILTER == []
total_issue = 0
total_projects = 0
project_names = $redmine_projects.collect { |p| p.name }
repos.each_page do |page|
  page.each do |repo|
    name = repo.name
    next if REPOSITORY_FILTER.size > 0 && !REPOSITORY_FILTER.include?(repo.name)
    puts "Processing Repo #{name}"
    open_issues = github.issues.list(user: ORGANIZATION, repo: name)
    puts "#{open_issues.size} open issues"
    closed_issues = github.issues.list(user: ORGANIZATION, repo: name, state: 'closed')
    puts "#{closed_issues.size} closed issues"
    puts "Enter name of Redmine project - type 'skip' to skip - (#{name})"
    puts "Available projects #{project_names}"
    redmine_project = gets.chomp
    redmine_project = name if redmine_project == ''
    closed_versions = []
    if redmine_project == 'skip'
      puts "Skipping #{name}"
    else
      project = find_project(redmine_project)
      total_projects += 1
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
      $redmine_projects = Project.find(:all, params: { limit: 100 })

      project  = Project.find(project.id, params: {include: 'trackers'})
      memberships = Membership.find(:all, params: {project_id: project.id})
      add_members_to_project_mapping(project, memberships)
      tracker = nil
      if DEFAULT_TRACKER == '' || DEFAULT_TRACKER.nil?
        puts "Available trackers: #{tracker_names}"
        puts "Select tracker: - (Feature)"
        tracker_name = gets.chomp
        tracker_name = 'Feature' if tracker_name == ''
        tracker = find_tracker(tracker_name)
      else
        tracker = find_tracker(DEFAULT_TRACKER)
      end
      if !project.trackers.include?(tracker)
        puts "saving tracker"
        project.trackers << tracker
        project.tracker_ids = project.trackers.collect {|t| t.id}
        project.save
      end
      puts "Processing open issues"
      count = 0
      open_issues.each_page do |page|
        page.each do |oi|
          description_text = "#{clean_pandoc(PandocRuby.convert(convert_code_blocks(oi.body), from: 'markdown_github', to: 'textile'))} \n--------------------------------------------------
\nGithub url: #{oi.html_url}"
          i = Issue.new project_id: project.id, status_id: open_issue_status.id, priority_id: normal_priority.id, subject: oi.title,
                    description: description_text.force_encoding('utf-8'), start_date: Time.parse(oi.created_at).to_date.to_s, tracker_id: tracker.id

          versions = Version.find(:all, :params => {project_id: project.id, limit: 100 })

          if !oi.milestone.nil?
            version = versions.find { |v| v.name.upcase == oi.milestone.title.upcase } unless versions.nil?
            if version.nil?
              version = Version.new name: oi.milestone.title, status: 'open', project_id: project.id
              version.effective_date = Date.parse(oi.milestone.due_on).to_s unless oi.milestone.due_on.nil?
              version.save!
              closed_versions << version if oi.milestone.state == 'closed'
              puts "versions saved"
            elsif version.status == 'closed'
              ver = UpdateVersion.find(version.id)
              ver.status = 'open'
              ver.save!
              closed_versions << ver
            end
            i.fixed_version_id = version.id
          end

          if !oi.labels.nil? && !oi.labels.empty?
            i.description += "\nNotes: #{oi.labels.collect {|label| label.name }.to_s}"
          end
          if !oi.user.nil?
            login = oi.user.login
            user = find_or_create_user(login)
            check_or_create_membership(project, user) unless user.nil?
            i.impersonate(user.login) unless user.nil?
          end
          if !oi.assignee.nil?
           login = oi.assignee.login
           user = find_or_create_user(login)
           i.assigned_to_id = user.id unless user.nil?
          end
          unless i.save
            puts "issue error #{i.errors.full_messages}"
          end
          i.remove_impersonation
          history_events = []
          github.issues.events.list(user: ORGANIZATION, repo: name, issue_id: oi.number).each_page do |page|
            page.each do |event|
              history_events << {type: event.event, user: event.actor.login, date: Time.parse(event.created_at)} if ['closed', 'reopened'].include? event.event
            end
          end
          if oi.comments > 0
            github.issues.comments.list(user: ORGANIZATION, repo: name, issue_id: oi.number).each_page do |page|
              page.each do |comment|
                history_events << {type: 'comment', date: Time.parse(comment.created_at), comment: comment}
              end
            end
          end
          history_events.sort! {|x,y| x[:date] <=> y[:date]}
          history_events.each do |event|
            if event[:type] == 'closed'
              login = event[:user]
              user = find_or_create_user(login)
              check_or_create_membership(project, user) unless user.nil?
              i.impersonate(user.login) unless user.nil?
              i.status_id = closed_issue_status.id
              unless i.save
                puts "issue error #{i.errors.full_messages}"
              end
              i.remove_impersonation
            end
            if event[:type] == 'reopened'
              login = event[:user]
              user = find_or_create_user(login)
              check_or_create_membership(project, user) unless user.nil?
              i.impersonate(user.login) unless user.nil?
              i.status_id = open_issue_status.id
              unless i.save
                puts "issue error #{i.errors.full_messages}"
              end
              i.remove_impersonation
            end
            if event[:type] == 'comment'
              comment = event[:comment]
              login = comment.user.login
              user = find_or_create_user(login)

              comment_text = clean_pandoc(PandocRuby.convert(convert_code_blocks(comment.body), from: 'markdown_github', to: 'textile'))
              check_or_create_membership(project, user) unless user.nil?
              i.impersonate(user.login) unless user.nil?
              i.notes = comment_text.force_encoding('utf-8')
              unless i.save
                puts "issue error #{i.errors.full_messages}"
              end
              i.remove_impersonation
            end
          end
          count += 1
          puts "Saved open issue #{count} out of #{open_issues.size}"
        end
      end
      total_issue += count
      puts "Processing closed issues"
      count = 0
      closed_issues.each_page do |page|
        page.each do |ci|
          description_text = "#{clean_pandoc(PandocRuby.convert(convert_code_blocks(ci.body), from: 'markdown_github', to: 'textile'))} \n--------------------------------------------------
\nGithub url: #{ci.html_url}"
          con = MyConn.new Issue.site, Issue.format
          con.user = Issue.user
          con.password = Issue.password
          Issue.connection = con
          i = Issue.new project_id: project.id, status_id: open_issue_status.id, priority_id: normal_priority.id, subject: ci.title, tracker_id: tracker.id,
                        description: description_text.force_encoding('utf-8'), start_date: Time.parse(ci.created_at).to_date.to_s, closed_on: Time.parse(ci.closed_at).to_s

          versions = Version.find(:all, :params => {:project_id => project.id})

          if !ci.milestone.nil?
            version = versions.find { |v| v.name.upcase == ci.milestone.title.upcase } unless versions.nil?
            if version.nil?
              version = Version.new name: ci.milestone.title, status: 'open', project_id: project.id
              version.effective_date = Date.parse(ci.milestone.due_on).to_s unless ci.milestone.due_on.nil?
              version.save!
              closed_versions << version if ci.milestone.state == 'closed'
            elsif version.status == 'closed'
              ver = UpdateVersion.find(version.id)
              ver.status = 'open'
              ver.save!
              closed_versions << ver
            end
            i.fixed_version_id = version.id
          end


          if !ci.labels.nil? && !ci.labels.empty?
            i.description += "\nNotes: #{ci.labels.collect {|label| label.name }.to_s}"
          end
          if !ci.user.nil?
            login = ci.user.login
            user = find_or_create_user(login)

            check_or_create_membership(project, user) unless user.nil?
            i.impersonate(user.login) unless user.nil?
          end
          if !ci.assignee.nil?
            login = ci.assignee.login
            user = find_or_create_user(login)

            i.assigned_to_id = user.id unless user.nil?
          end

          unless i.save
            puts "issue error #{i.errors.full_messages}"
          end
          i.remove_impersonation
          if CLOSE_DATE != 'none'
            if CLOSE_DATE == 'due_date'
              i.due_date = Date.parse(ci.closed_at).to_s
            else
              if i.respond_to? :custom_fields
                date_field =  i.custom_fields.find_index {|field| field.name.upcase == CLOSE_DATE.upcase }
                if !date_field.nil?
                  i.custom_fields[date_field].value = Date.parse(ci.closed_at).to_s
                  i.save!
                end
              end
            end
          end
          history_events = []
          github.issues.events.list(user: ORGANIZATION, repo: name, issue_id: ci.number).each_page do |page|
            page.each do |event|
              history_events << {type: event.event, user: event.actor.login, date: Time.parse(event.created_at)} if ['closed', 'reopened'].include? event.event
            end
          end
          if ci.comments > 0
            github.issues.comments.list(user: ORGANIZATION, repo: name, issue_id: ci.number).each_page do |page|
              page.each do |comment|
                history_events << {type: 'comment', date: Time.parse(comment.created_at), comment: comment}
              end
            end
          end
          history_events.sort! {|x,y| x[:date] <=> y[:date]}
          history_events.each do |event|
            if event[:type] == 'closed'
              login = event[:user]
              user = find_or_create_user(login)
              check_or_create_membership(project, user) unless user.nil?
              i.impersonate(user.login) unless user.nil?
              i.status_id = closed_issue_status.id
              unless i.save
                puts "issue error #{i.errors.full_messages}"
                puts con.last_resp.body.inspect
              end
              i.remove_impersonation
            end
            if event[:type] == 'reopened'
              login = event[:user]
              user = find_or_create_user(login)
              check_or_create_membership(project, user) unless user.nil?
              i.impersonate(user.login) unless user.nil?
              i.status_id = open_issue_status.id
              unless i.save
                puts "issue error #{i.errors.full_messages}"
                puts con.last_resp.body.inspect
              end
              i.remove_impersonation
            end
            if event[:type] == 'comment'
              comment = event[:comment]
              login = comment.user.login
              user = find_or_create_user(login)
              comment_text = clean_pandoc(PandocRuby.convert(convert_code_blocks(comment.body), from: 'markdown_github', to: 'textile'))
              check_or_create_membership(project, user) unless user.nil?
              i.impersonate(user.login) unless user.nil?
              i.notes = comment_text.force_encoding('utf-8')
              unless i.save
                puts "issue error #{i.errors.full_messages}"
                puts con.last_resp.body.inspect
              end
              i.remove_impersonation
            end
          end
          count += 1
          puts "Saved closed issue #{count} out of #{closed_issues.size}"
        end
      end
      total_issue += count
      closed_versions.each do |cv|
        version = UpdateVersion.find(cv.id)
        version.status = 'closed'
        version.project_id = project.id
        version.save!
      end
    end
  end
end

interval = (Time.now - start_time).to_i
seconds = interval % 60
minutes = (interval / 60) % 60
hours = ((interval / 60) / 60 ) % 60
seconds = "0#{seconds}" if seconds < 10
minutes = "0#{minutes}" if minutes < 10
hours = "0#{hours}" if hours < 10
puts "Import took #{hours}:#{minutes}:#{seconds}"
puts "Imported #{total_issue} issues across #{total_projects} projects"
#encoding: utf-8
require 'rubygems'
gem 'activeresource', '~> 3.2.12'
require 'active_resource'
require 'github_api'
require 'pandoc-ruby.rb'
require 'yaml'

config = YAML.load_file('config.yml')
REDMINE_SITE = config['REDMINE_SITE']
REDMINE_TOKEN = config['REDMINE_TOKEN']
ORGANIZATION  = config['ORGANIZATION']
GITHUB_TOKEN = config['GITHUB_TOKEN']
single_repo = config['SINGLE_REPO']

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
puts 'Name of open issue status - (Backlog)'
open_issue_status_name = gets.chomp
open_issue_status_name = 'Backlog' if open_issue_status_name == ''
open_issue_status = issue_statuses.detect { |is| is.name.upcase == open_issue_status_name.upcase}
puts 'Name of closed issue status - (Done)'
closed_issue_status_name = gets.chomp
closed_issue_status_name = 'Done' if closed_issue_status_name == ''
closed_issue_status = issue_statuses.detect { |is| is.name.upcase == closed_issue_status_name.upcase}
puts 'Name of normal priority - (normal)'
normal_priority_name = gets.chomp
normal_priority_name = 'normal' if normal_priority_name == ''
normal_priority = IssuePriority.all.detect { |ip| ip.name.upcase == normal_priority_name.upcase }
$redmine_projects = Project.find(:all, params: { limit: 100 })
$trackers = Tracker.all
$users = User.all
roles = Role.all
puts 'Name of default role - (reporter)'
reporter_name = gets.chomp
reporter_name = 'reporter' if reporter_name == ''
$reporter = Role.all.find { |role| role.name.upcase == reporter_name.upcase }
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
puts "Only processing #{single_repo}" unless single_repo == ''
project_names = $redmine_projects.collect { |p| p.name }
repos.each_page do |page|
  page.each do |repo|
    name = repo.name
    next if single_repo != '' && name.upcase != single_repo.upcase
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
      puts "Available trackers: #{tracker_names}"
      puts "Select tracker: - (Feature)"
      tracker_name = gets.chomp
      tracker_name = 'Feature' if tracker_name == ''
      tracker = find_tracker(tracker_name)
      if !project.trackers.include?(tracker)
        puts "saving tracker"
        project.trackers << tracker
        project.tracker_ids = project.trackers.collect {|t| t.id}
        project.save
      end
      puts "Processing open issues"
      open_issues.each_page do |page|
        page.each do |oi|
          description_text = "#{PandocRuby.convert(convert_code_blocks(oi.body), from: 'markdown_github', to: 'textile')} \n--------------------------------------------------
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
          if i.save
            puts "issue saved"
          else
            puts "issue error #{i.errors.full_messages}"
          end
          i.remove_impersonation
          if oi.comments > 0
            github.issues.comments.list(user: ORGANIZATION, repo: name, issue_id: oi.number).each_page do |page|
              page.each do |comment|
                login = comment.user.login
                user = find_or_create_user(login)

                comment_text = PandocRuby.convert(convert_code_blocks(comment.body), from: 'markdown_github', to: 'textile')
                check_or_create_membership(project, user) unless user.nil?
                i.impersonate(user.login) unless user.nil?
                i.notes = comment_text.force_encoding('utf-8')
                i.save!
                i.remove_impersonation
              end
            end
          end
        end
      end
      puts "Processing closed issues"
      closed_issues.each_page do |page|
        page.each do |ci|
          description_text = "#{PandocRuby.convert(convert_code_blocks(ci.body), from: 'markdown_github', to: 'textile')} \n--------------------------------------------------
\nGithub url: #{ci.html_url}"
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

          if i.save!
            puts "issue saved"
          else
            puts "issue error #{i.errors.full_messages}"
          end
          i.remove_impersonation
          if ci.comments > 0
            github.issues.comments.list(user: ORGANIZATION, repo: name, issue_id: ci.number).each_page do |page|
              page.each do |comment|
                login = comment.user.login
                user = find_or_create_user(login)

                comment_text = PandocRuby.convert(convert_code_blocks(comment.body), from: 'markdown_github', to: 'textile')
                check_or_create_membership(project, user) unless user.nil?
                i.impersonate(user.login) unless user.nil?
                i.notes = comment_text.force_encoding('utf-8')
                i.save!
                i.remove_impersonation
              end
            end
          end
          i.notes = ''
          if i.respond_to? :custom_fields
            date_field =  i.custom_fields.find_index {|field| field.name.upcase == 'close_date'.upcase }
            if !date_field.nil?
              i.custom_fields[date_field].value = Date.parse(ci.closed_at).to_s
              i.save!
            end
          end
          i.remove_impersonation
          i.status_id = closed_issue_status.id
          i.save!
        end
      end
      closed_versions.each do |cv|
        version = UpdateVersion.find(cv.id)
        version.status = 'closed'
        version.project_id = project.id
        version.save!
      end
    end
  end
end
Github-to-Redmine import script utility
===

### 1. Prerequisites

Ruby 1.9.3 or higher, rails 3.2.12 or higher, github_api gem and [pandoc 1.11.1](http://johnmacfarlane.net/pandoc/index.html). To install the gems run
````
gem install rails -v '3.2.14'
gem install github_api
````
To install Pandoc, you can either follow instructions to install from source ( http://johnmacfarlane.net/pandoc/installing.html ) or use this [.deb package](http://archive.ubuntu.com/ubuntu/pool/universe/p/pandoc/pandoc_1.11.1-2build2_amd64.deb)

Also, you have to enable Redmine Api by checking `Enable REST web service` in `Administration>Settings>Authentication` in Redmine.

### 2. Configuration

Open `config.yml` and fill in your Redmine site address, Redmine API key, Github token and your organization name

````
REDMINE_TOKEN: '5eba716ilikenumbers4aa93049f1ccf2ea'
REDMINE_SITE: 'http://0.0.0.0:3000'
GITHUB_TOKEN: '5eba716ilikenumbers4aa93049f1ccf2ea'
ORGANIZATION: 'organization_name'
````

The user should be an administrator. And you should have a custom_field called `close_date` with type date, avalailable for all projects.

### 3. Running the script

You can run the script with
````
ruby import.rb
````

The script will guide you through importing.

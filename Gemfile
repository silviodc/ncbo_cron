source 'https://rubygems.org'

gemspec

gem 'rake'
gem 'pry'
gem 'multi_json'
gem 'redis'
gem 'minitest', '< 5.0'

# Monitoring
gem 'cube-ruby', require: 'cube'

# NCBO gems (can be from a local dev path or from rubygems/git)
ncbo_branch = ENV["NCBO_BRANCH"] || `git rev-parse --abbrev-ref HEAD`.strip || "staging"
gem 'goo', github: 'ncbo/goo', branch: ncbo_branch
gem 'sparql-client', github: 'ncbo/sparql-client', branch: ncbo_branch
gem 'ontologies_linked_data', github: 'ncbo/ontologies_linked_data', branch: ncbo_branch
gem 'ncbo_annotator', github: 'ncbo/ncbo_annotator', branch: ncbo_branch
source 'https://rubygems.org'

gem 'rake'
gem 'pry'
gem 'multi_json'
gem 'redis'
gem 'minitest', '< 5.0'

# Schedule-related gems
gem 'mlanett-redis-lock', require: 'redis-lock'
gem 'rufus-scheduler'
gem 'dante'

# NCBO gems (can be from a local dev path or from rubygems/git)
gemfile_local = File.expand_path("../Gemfile.local", __FILE__)

if File.exists?(gemfile_local)
  self.instance_eval(Bundler.read_file(gemfile_local))
else
  gem 'sparql-client', :git => 'https://github.com/ncbo/sparql-client.git'
  gem 'goo', :git => 'https://github.com/ncbo/goo.git'
  gem 'ontologies_linked_data', :git => 'https://github.com/ncbo/ontologies_linked_data.git'
  gem 'ncbo_annotator', :git => 'https://github.com/ncbo/ncbo_annotator.git'
end

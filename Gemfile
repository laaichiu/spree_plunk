source 'https://rubygems.org'

gem 'rails-controller-testing'

# Keep the default bundle within the supported Spree 6.0 line; use SPREE_PATH to
# audit the extension against a local Spree checkout.
if ENV['SPREE_PATH']
  gem 'spree', path: ENV['SPREE_PATH'], glob: 'spree/**/*.gemspec'
else
  gem 'spree', '~> 6.0.0'
end

gem 'spree_dev_tools', '1.0.0.beta2'
gem 'spree_plunk', path: '.'
gem 'dotenv'
gem 'webmock'

if ENV['DB'] == 'mysql'
  gem 'mysql2'
elsif ENV['DB'] == 'postgres'
  gem 'pg'
else
  gem 'sqlite3'
end

gem 'propshaft'

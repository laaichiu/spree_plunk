# encoding: UTF-8
lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'spree_plunk/version'

Gem::Specification.new do |s|
  s.platform = Gem::Platform::RUBY
  s.name = 'spree_plunk'
  s.version = SpreePlunk::VERSION
  s.summary = 'Spree Commerce integration for Plunk contact sync and event tracking'
  s.required_ruby_version = '>= 3.2'

  s.author = 'spree_plunk contributors'
  s.homepage = 'https://github.com/laaichiu/spree_plunk'
  s.license = 'MIT'

  s.metadata = {
    'bug_tracker_uri' => 'https://github.com/laaichiu/spree_plunk/issues',
    'changelog_uri' => 'https://github.com/laaichiu/spree_plunk/releases',
    'documentation_uri' => 'https://github.com/laaichiu/spree_plunk#readme',
    'source_code_uri' => 'https://github.com/laaichiu/spree_plunk'
  }

  s.files = Dir['{app,config,db,docs,lib,plunk_templates,script,vendor}/**/*', 'Rakefile', 'README.md'].reject do |file|
    file.match(/^spec/) && !file.match(/^spec\/fixtures/)
  end
  s.require_path = 'lib'
  s.requirements << 'none'

  # Core provides email template registration and rendering; the Admin API
  # exposes the editor and integration settings to the Spree dashboard.
  s.add_dependency 'spree_core', '>= 6.0.0', '< 6.1'
  s.add_dependency 'spree_api', '>= 6.0.0', '< 6.1'

  s.add_development_dependency 'dotenv'
  s.add_development_dependency 'rubocop-rspec'
  s.add_development_dependency 'spree_dev_tools', '>= 1.0.0.beta2'
  s.add_development_dependency 'webmock'
  s.add_development_dependency 'i18n-tasks'
end

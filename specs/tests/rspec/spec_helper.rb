# frozen_string_literal: true

require 'bundler/setup'
require 'releasehx'
require 'yaml'
require 'json'
require 'tempfile'
require 'tmpdir'
require_relative '../../../lib/schemagraphy/safe_expression'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

# Helper methods for tests
def create_temp_yaml_file content
  file = Tempfile.new(['test', '.yml'])
  if content.is_a?(Hash)
    file.write(YAML.dump(content))
  else
    file.write(content)
  end
  file.close
  file.path
end

def create_temp_json_file content
  file = Tempfile.new(['test', '.json'])
  if content.is_a?(Hash) || content.is_a?(Array)
    file.write(JSON.pretty_generate(content))
  else
    file.write(content)
  end
  file.close
  file.path
end

def create_temp_dir
  Dir.mktmpdir('releasehx_test_')
end

def sample_release_config
  {
    'project' => 'test/repo',
    'version' => '1.0.0',
    'source' => 'json',
    'output_format' => 'markdown',
    'template' => 'default'
  }
end

def sample_release_issues_json
  [
    {
      'number' => 1,
      'title' => 'Fix authentication bug',
      'body' => 'Authentication fails when using token',
      'labels' => [{ 'name' => 'bug' }, { 'name' => 'priority:high' }],
      'assignees' => [{ 'login' => 'developer1' }],
      'milestone' => { 'title' => '1.0.0' },
      'state' => 'closed'
    },
    {
      'number' => 2,
      'title' => 'Add new feature',
      'body' => 'Implement user dashboard',
      'labels' => [{ 'name' => 'enhancement' }, { 'name' => 'priority:medium' }],
      'assignees' => [{ 'login' => 'developer2' }],
      'milestone' => { 'title' => '1.0.0' },
      'state' => 'closed'
    }
  ]
end

def sample_rhyml_content
  {
    'project' => 'Test Project',
    'version' => '1.0.0',
    'date' => '2025-01-01',
    'changes' => [
      {
        'type' => 'feature',
        'title' => 'Add new authentication system',
        'description' => 'Implemented OAuth2 support for better security'
      },
      {
        'type' => 'bug',
        'title' => 'Fix memory leak in data processing',
        'description' => 'Resolved issue causing excessive memory usage'
      }
    ]
  }
end

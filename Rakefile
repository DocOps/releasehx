# frozen_string_literal: true

require 'rake'
require 'yaml'

# Load DocOps Lab development tasks
begin
  require 'docopslab/dev'
rescue LoadError
  # Skip if not available (e.g., production environment)
end

BUILDER_NAME = 'releasehx-builder'
VERSION_LINE_REGEX = /^:this_prod_vrsn:\s+(.*)$/

# Only require rspec when running spec tasks
begin
  require 'rspec/core/rake_task'

  RSpec::Core::RakeTask.new(:rspec) do |t|
    t.pattern = 'specs/tests/rspec/**/*_spec.rb'
  end

  task default: :rspec
rescue LoadError
  # RSpec not available - skip test tasks
end

task :prebuild do
  require_relative 'lib/sourcerer'
  srcrr_config = YAML.safe_load_file('.config/sourcerer.yml', symbolize_names: true, aliases: true)

  Sourcerer::Builder.generate_prebuild(**srcrr_config)
  render_config = srcrr_config[:render] || srcrr_config[:templates] || []
  Sourcerer.render_outputs(render_config)
  require_relative 'lib/releasehx/mcp'
  ReleaseHx::MCP::AssetPackager.new.package!
  Sourcerer.generate_manpage('docs/manpage.adoc', 'build/docs/releasehx.1')
end

desc 'Build and tag multi-arch Docker image for releasehx'
task buildx: :prebuild do
  ensure_buildx_builder
  version = extract_version

  sh 'docker buildx build --platform linux/amd64 ' \
     "--build-arg RELEASEHX_VERSION=#{version} " \
     '-t docopslab/releasehx:latest ' \
     "-t docopslab/releasehx:#{version} " \
     '.'
end

desc 'Build the gem (run `prebuild` first)'
task prebundle: :prebuild do
  mkdir_p 'pkg'
  sh 'gem build releasehx.gemspec'
  sh 'mv releasehx-*.gem pkg/'
end

desc 'Run CLI tests'
task :cli_test do
  puts 'Testing CLI functionality...'
  puts 'Checking that CLI files exist...'
  unless File.exist?('bin/rhx')
    puts '✗ bin/rhx not found'
    exit 1
  end
  puts '✓ bin/rhx exists'
  puts 'Note: Full CLI testing requires prebuild step for attributes'
end

desc 'Smoke test MCP server resources'
task :mcp_test do
  require_relative 'lib/releasehx/mcp'

  server = ReleaseHx::MCP::Server.new
  expected = [
    'releasehx://agent/guide',
    'releasehx://config/sample',
    'releasehx://config/schema',
    'releasehx://config/reference.json',
    'releasehx://config/reference.adoc'
  ]

  resources = server.list_resources
  missing = expected - resources
  unless missing.empty?
    puts "✗ Missing MCP resources: #{missing.join(', ')}"
    exit 1
  end

  begin
    server.get_resource('releasehx://agent/guide')
  rescue Errno::ENOENT => e
    puts "✗ #{e.message}"
    exit 1
  end

  response = server.send(:handle_tool, 'config.reference.get', { pointer: '/properties/origin' }, nil)
  unless response.is_a?(MCP::Tool::Response) && response.structured_content
    puts '✗ MCP tool response missing structured content'
    exit 1
  end

  puts '✓ MCP smoke test passed'
end

desc 'Validate YAML examples'
task :yaml_test do
  puts 'Validating YAML examples...'
  buckets = {
    'Test configs' => 'specs/tests/configs/*.yml',
    'RHYML mappings' => 'lib/releasehx/rhyml/mappings/*.{yml,yaml}',
    'Schemas' => 'specs/data/*-schema.yaml'
  }

  buckets.each do |label, pattern|
    files = Dir.glob(pattern)
    puts "#{label}: #{files.size} file(s)"
    files.each do |file|
      puts "Validating #{file}"
      begin
        YAML.safe_load_file(file, aliases: true)
        puts "✓ #{file} is valid"
      rescue StandardError => e
        puts "✗ #{file} failed: #{e.message}"
        exit 1
      end
    end
  end
end

desc 'Run bundle install'
task :install do
  sh 'bundle install'
end

desc 'Run all PR tests locally (same as GitHub Actions)'
task :pr_test do
  puts '🔍 Running all PR tests locally...'
  puts '\n=== RSpec Tests ==='
  Rake::Task[:rspec].invoke

  puts '\n=== CLI Tests ==='
  Rake::Task[:cli_test].invoke

  puts '\n=== YAML Validation ==='
  Rake::Task[:yaml_test].invoke

  puts '\n✅ All PR tests passed!'
end

desc 'Build and install gem locally'
task install_local: :prebundle do
  sh 'gem install pkg/releasehx-*.gem'
end

desc 'Build the gem with prebuild artifacts'
task build: :prebundle

desc 'Test commands in README.adoc'
task :readme_test do
  require_relative 'lib/sourcerer'
  puts 'Executing testable commands from README.adoc'
  command_groups = Sourcerer.extract_commands('README.adoc', role: 'testable')
  demo_dir = '../releasehx-demo'
  unless Dir.exist?(demo_dir)
    puts 'Note: README command tests require the releasehx-demo repo.'
    next
  end
  Dir.chdir(demo_dir) do
    command_groups.each do |group|
      sh "shopt -s expand_aliases; #{group}" unless group.strip.empty?
    end
  end
end

desc 'Generate rich-text documentation from source with Jekyll and Yard'
task docs: :prebuild do
  require_relative 'scripts/build_docs'
  version = extract_version
  DocOpsLab::DocBuilder.build_docs version
end

desc 'Spins up a local HTTP server to serve the docs'
# takes argument --port=N to specify port (default 8000)
task :serve do
  port = ENV['PORT'] ? ENV['PORT'].to_i : 8000
  Dir.chdir('build/docs') do
    sh "bundle exec jekyll serve --port #{port} --skip-initial-build --destination _site"
  end
  puts "Serving docs at http://localhost:#{port}"
end

def extract_version
  attrs = readme_attrs
  return attrs['this_prod_vrsn'].strip if attrs['this_prod_vrsn']

  raise 'Version not found in README.adoc'
end

def readme_attrs
  require_relative 'lib/sourcerer'
  Sourcerer.load_attributes('README.adoc')
end

def ensure_buildx_builder
  builders = `docker buildx ls`
  return if builders.include?(BUILDER_NAME)

  puts "Creating buildx builder '#{BUILDER_NAME}'..."
  sh "docker buildx create --name #{BUILDER_NAME} --driver docker-container --use"
  sh "docker buildx inspect --builder #{BUILDER_NAME} --bootstrap"
end

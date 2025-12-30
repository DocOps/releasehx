#!/usr/bin/env ruby
# frozen_string_literal: true

# API Authentication Test for ReleaseHx 0.1.0
# Tests authentication and basic functionality for GitHub, GitLab, and Jira APIs

# Add lib path to load path
lib_path = File.expand_path('../../lib', __dir__)
$LOAD_PATH.unshift(lib_path) unless $LOAD_PATH.include?(lib_path)

require 'yaml'
require 'json'
require_relative '../../lib/releasehx/rest/yaml_client'
require_relative '../../lib/releasehx'

class ApiAuthTester
  # Use existing demo configs to avoid duplication
  DEMO_CONFIGS = {
    github: 'specs/tests/configs/github-api-test.yml',
    gitlab: 'specs/tests/configs/gitlab-api-test.yml'
  }.freeze

  ENV_VARS = {
    github: ['GITHUB_TOKEN'],
    gitlab: ['GITLAB_TOKEN'],
    jira: %w[JIRA_USERNAME JIRA_API_TOKEN]
  }.freeze

  def self.test_all
    puts 'ReleaseHx API Authentication Test Suite'
    puts '=' * 50

    missing_any = ENV_VARS.values.flatten.uniq.select { |var| ENV[var].to_s.empty? }
    unless missing_any.empty?
      puts 'Skipping API auth tests (missing required env vars):'
      puts "  #{missing_any.join(', ')}"
      puts 'Set these in your shell to run the live API checks.'
      return
    end

    results = {}
    ENV_VARS.each_key do |platform|
      puts "\nTesting #{platform.upcase}..."
      results[platform] = test_platform(platform)
    end

    report_results(results)
  end

  def self.test_platform platform
    # Check environment variables
    missing_vars = ENV_VARS[platform].select { |var| ENV[var].nil? || ENV[var].empty? }
    unless missing_vars.empty?
      puts "  ❌ Missing: #{missing_vars.join(', ')}"
      return { status: 'fail', error: 'Missing environment variables', missing: missing_vars }
    end
    puts '  ✅ Environment variables present'

    # Load config (use demo config if available, otherwise create minimal)
    config = load_config(platform)
    unless config
      puts '  ❌ Configuration loading failed'
      return { status: 'fail', error: 'Configuration loading failed' }
    end
    puts '  ✅ Configuration loaded'

    # Test API client creation and basic functionality
    begin
      client = ReleaseHx::REST::YamlClient.new(config, '1.0.0')
      puts '  ✅ API client created'

      # Attempt to fetch (will likely fail but tests auth)
      issues = client.fetch_all
      puts "  ✅ API call successful (#{issues.length} issues found)"
      { status: 'pass', issues_found: issues.length }
    rescue StandardError => e
      error_msg = e.message
      if error_msg.include?('401')
        puts "  ❌ Authentication failed: #{error_msg}"
        { status: 'fail', error: 'Authentication failed' }
      elsif error_msg.include?('404')
        puts '  ⚠️  Authentication OK, but repository/project not found'
        { status: 'warning', error: 'Repository/project not configured' }
      else
        puts "  ⚠️  Client created, API error: #{error_msg}"
        { status: 'warning', error: error_msg }
      end
    end
  end

  def self.load_config platform
    if DEMO_CONFIGS[platform] && File.exist?(DEMO_CONFIGS[platform])
      YAML.load_file(DEMO_CONFIGS[platform])
    else
      # Create minimal config for platforms without demo configs (e.g., Jira)
      create_minimal_config(platform)
    end
  rescue StandardError => e
    puts "  ❌ Config loading error: #{e.message}"
    nil
  end

  def self.create_minimal_config platform
    case platform
    when :jira
      {
        'source' => { 'type' => 'jira', 'version' => 2 },
        'conversions' => { 'summ' => 'issue_heading', 'note' => 'issue_body' },
        'tags' => { '_include' => %w[bug enhancement] }
      }
    end
  end

  def self.report_results results
    puts '\n" + "=' * 50
    puts 'SUMMARY'
    puts '=' * 50

    passed = results.values.count { |r| r[:status] == 'pass' }
    warned = results.values.count { |r| r[:status] == 'warning' }
    failed = results.values.count { |r| r[:status] == 'fail' }

    puts "✅ Passed: #{passed}"
    puts "⚠️  Warnings: #{warned}" if warned.positive?
    puts "❌ Failed: #{failed}" if failed.positive?

    if failed.zero? && warned.zero?
      puts '\n🎉 All API platforms working correctly!'
    elsif failed.zero?
      puts '\n✅ Authentication successful, check repository/project configuration'
    else
      puts '\n❌ Some platforms need attention - check environment variables and tokens'
    end
  end
end

# Run if called directly
ApiAuthTester.test_all if __FILE__ == $PROGRAM_NAME

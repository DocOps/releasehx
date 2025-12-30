# frozen_string_literal: true

require 'thor'
require 'logger'
require 'liquid'
require 'yaml'
require_relative 'sourcerer'
require_relative 'schemagraphy'
begin
  require_relative 'releasehx/generated'
rescue LoadError
  raise LoadError, 'ReleaseHx prebuild artifacts missing. Run `bundle exec rake prebuild`.'
end
require_relative 'releasehx/helpers'
require_relative 'releasehx/configuration'
require_relative 'releasehx/rhyml'
require_relative 'releasehx/version'
require_relative 'releasehx/sgyml/helpers'
require_relative 'releasehx/ops/template_ops'
require_relative 'releasehx/ops/check_ops'
require_relative 'releasehx/ops/draft_ops'
require_relative 'releasehx/ops/write_ops'
require_relative 'releasehx/ops/enrich_ops'
require_relative 'releasehx/rest/yaml_client'
require_relative 'releasehx/transforms/adf_to_markdown'

# The ReleaseHx module provides a CLI and a library for generating release
# histories and changelogs from various sources like Jira, GitHub, and YAML files.
module ReleaseHx
  def self.attrs
    if ENV['RELEASEHX_DEV_RELOAD'] == 'true'
      # Development-only reload from source document
      require 'asciidoctor' # explicitly required here for dev-only reload
      Sourcerer.load_attributes(File.expand_path('../README.adoc', __dir__))
    else
      # Always use pre-generated attributes at runtime
      ReleaseHx::ATTRIBUTES[:globals]
    end
  end

  DUMP = Logger::DEBUG - 1 # Custom log level, lower than DEBUG

  class << self
    # Provides a singleton logger instance for the application.
    #
    # @return [Logger] The application-wide logger instance.
    def logger
      return @logger if @logger

      $stdout.sync = true
      log = Logger.new($stdout)
      log.level = Logger::INFO
      log.formatter = proc do |severity, _datetime, _progname, msg|
        sev = severity == DUMP ? 'DUMP' : severity
        "#{sev}: #{msg}\n"
      end

      log.singleton_class.class_eval do
        define_method(:dump) do |msg|
          add(DUMP, msg)
        end
      end

      @logger = log
    end
  end

  class Error < StandardError; end
end

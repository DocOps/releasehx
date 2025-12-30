# frozen_string_literal: true

require 'English'
require_relative 'spec_helper'
require 'tempfile'

RSpec.describe 'ReleaseHx Dependencies' do
  describe 'Sourcerer Integration' do
    it 'provides version and help information to CLI' do
      system('rake prebuild') unless File.exist?('lib/releasehx/generated.rb')

      # Test CLI help includes version from Sourcerer
      help_output = `bundle exec bin/releasehx --help 2>&1`
      expect(help_output).to include('ReleaseHx')
      expect(help_output).to match(/\d+\.\d+\.\d+/) # Version number
    end

    it 'CLI version command works' do
      version_output = `bundle exec bin/releasehx --version 2>&1`
      expect($CHILD_STATUS.success?).to be true
      expect(version_output).to match(/\d+\.\d+\.\d+/)
    end
  end

  describe 'SchemaGraphy Integration' do
    it 'loads ReleaseHx configurations with templated fields' do
      # Create a minimal test config
      config_content = <<~YAML
        origin:
          source: github
          href: "https://api.github.com/repos/owner/repo/issues"
        templates:
          output: "{{ version }}.md"
        version: "1.0.0"
      YAML

      temp_file = Tempfile.new(['config', '.yml'])
      temp_file.write(config_content)
      temp_file.close

      begin
        config = ReleaseHx::Configuration.load(temp_file.path)
        expect(config).to be_a(ReleaseHx::Configuration)
        expect(config.origin['source']).to eq('github')
      ensure
        temp_file.unlink
      end
    end
  end

  describe 'Template System' do
    it 'processes Liquid templates in output generation' do
      # This tests that the template system works end-to-end
      # without deep-diving into SchemaGraphy internals
      temp_output = Dir.mktmpdir
      temp_json = create_temp_json_file(sample_release_issues_json)
      temp_config = Tempfile.new(['config', '.yml'])
      temp_config.write(<<~YAML)
        origin:
          source: github
        paths:
          drafts_dir: .
          output_dir: #{temp_output}
      YAML
      temp_config.close

      begin
        result = system("bundle exec bin/releasehx 1.0.0 --config #{temp_config.path} " \
                        "--api-data #{temp_json} --md #{temp_output}/output.md --force")
        expect(result).to be(true), 'Template processing failed with sample data'

        # Should have generated some output files
        output_files = Dir.glob("#{temp_output}/**/*").select { |f| File.file?(f) }
        expect(output_files).not_to be_empty, 'No output files generated'
      ensure
        FileUtils.rm_rf(temp_output)
        FileUtils.rm_f(temp_json)
        temp_config.unlink
      end
    end
  end
end

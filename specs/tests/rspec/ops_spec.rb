# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'ReleaseHx Operations' do
  describe 'operation modules' do
    it 'loads TemplateOps without errors' do
      expect { require 'releasehx/ops/template_ops' }.not_to raise_error
    end

    it 'loads CheckOps without errors' do
      expect { require 'releasehx/ops/check_ops' }.not_to raise_error
    end

    it 'loads DraftOps without errors' do
      expect { require 'releasehx/ops/draft_ops' }.not_to raise_error
    end

    it 'loads WriteOps without errors' do
      expect { require 'releasehx/ops/write_ops' }.not_to raise_error
    end

    it 'loads EnrichOps without errors' do
      expect { require 'releasehx/ops/enrich_ops' }.not_to raise_error
    end
  end

  # Basic integration tests using sample data from demo
  describe 'data processing workflow' do
    let(:temp_dir) { create_temp_dir }
    let(:sample_json_file) { create_temp_json_file(sample_release_issues_json) }
    let(:sample_config_file) { create_temp_yaml_file(sample_release_config) }

    after do
      FileUtils.rm_rf(temp_dir)
      FileUtils.rm_f(sample_json_file)
      FileUtils.rm_f(sample_config_file)
    end

    it 'can read sample JSON data' do
      json_data = JSON.parse(File.read(sample_json_file))
      expect(json_data).to be_an(Array)
      expect(json_data.length).to eq(2)
      expect(json_data.first).to have_key('title')
    end

    it 'can read sample YAML config' do
      config_data = YAML.load_file(sample_config_file)
      expect(config_data).to be_a(Hash)
      expect(config_data).to have_key('project')
      expect(config_data).to have_key('version')
    end
  end

  describe 'template processing' do
    it 'validates template system availability' do
      # Test that Liquid templating is available
      expect(defined?(Liquid)).not_to be_nil
    end

    it 'can create basic liquid template' do
      template_content = '# Release {{ version }}'
      template = Liquid::Template.parse(template_content)
      result = template.render('version' => '1.0.0')
      expect(result).to eq('# Release 1.0.0')
    end
  end
end

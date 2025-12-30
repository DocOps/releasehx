# frozen_string_literal: true

require_relative '../spec_helper'
require 'schemagraphy/cfgyml/definition'

RSpec.describe SchemaGraphy::CFGYML::Definition do
  let(:test_schema) do
    {
      'properties' => {
        'paths' => {
          'properties' => {
            'drafts_dir' => {
              'dflt' => '{default_drafts_dir}'
            },
            'enrich_dir' => {
              'dflt' => '{default_enrich_dir}'
            }
          }
        }
      }
    }
  end

  let(:test_attrs) do
    {
      'default_drafts_dir' => '_drafts',
      'default_enrich_dir' => '_publish'
    }
  end

  let(:temp_schema_file) { create_temp_yaml_file(test_schema) }

  after do
    FileUtils.rm_f(temp_schema_file)
  end

  describe '#initialize' do
    it 'loads schema with resolved attributes' do
      cfgyml = described_class.new temp_schema_file, test_attrs

      expect(cfgyml.schema.dig('properties', 'paths', 'properties', 'drafts_dir', 'dflt'))
        .to eq('_drafts')
      expect(cfgyml.schema.dig('properties', 'paths', 'properties', 'enrich_dir', 'dflt'))
        .to eq('_publish')
    end
  end

  describe '#template_paths' do
    it 'includes default CFGYML template path' do
      cfgyml = described_class.new temp_schema_file, test_attrs
      expect(cfgyml.template_paths.first).to include('templates/cfgyml')
    end
  end

  describe '#render_reference' do
    context 'with adoc format' do
      it 'renders the config reference template successfully' do
        cfgyml = described_class.new temp_schema_file, test_attrs
        result = cfgyml.render_reference(:adoc)
        expect(result).to be_a(String)
        expect(result.length).to be_positive
      end
    end

    context 'with yaml format' do
      it 'renders the sample config template successfully' do
        cfgyml = described_class.new temp_schema_file, test_attrs
        result = cfgyml.render_reference(:yaml)
        expect(result).to be_a(String)
        expect(result.length).to be_positive
      end
    end

    context 'with invalid format' do
      it 'raises an error' do
        cfgyml = described_class.new temp_schema_file, test_attrs
        expect { cfgyml.render_reference(:invalid) }
          .to raise_error(ArgumentError, /Unsupported format: invalid/)
      end
    end
  end
end

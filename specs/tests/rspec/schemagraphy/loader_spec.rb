# frozen_string_literal: true

require_relative '../spec_helper'
require 'schemagraphy/loader'

RSpec.describe SchemaGraphy::Loader do
  describe '.load_yaml_with_attributes (internal functionality)' do
    let(:test_yaml) do
      <<~YAML
        properties:
          field1:
            dflt: '{attr1}'
          field2:
            nested:
              dflt: '{attr2}'
          field3:
            dflt: 'literal_value'
      YAML
    end

    let(:test_attrs) do
      {
        'attr1' => 'resolved1',
        'attr2' => 'resolved2'
      }
    end

    let(:temp_yaml_file) { create_temp_yaml_file(test_yaml) }

    after do
      FileUtils.rm_f(temp_yaml_file)
    end

    it 'resolves attribute references in nested dflt values' do
      result = described_class.load_yaml_with_attributes temp_yaml_file, test_attrs

      expect(result.dig('properties', 'field1', 'dflt')).to eq('resolved1')
      expect(result.dig('properties', 'field2', 'nested', 'dflt')).to eq('resolved2')
      expect(result.dig('properties', 'field3', 'dflt')).to eq('literal_value')
    end

    it 'preserves unmatched attribute references' do
      result = described_class.load_yaml_with_attributes temp_yaml_file, {}

      expect(result.dig('properties', 'field1', 'dflt')).to eq('{attr1}')
      expect(result.dig('properties', 'field2', 'nested', 'dflt')).to eq('{attr2}')
    end

    it 'handles empty files gracefully' do
      empty_file = create_temp_yaml_file('')
      result = described_class.load_yaml_with_attributes empty_file, test_attrs
      expect(result).to eq({})
      File.unlink(empty_file)
    end
  end

  describe '.load_yaml_with_tags (existing functionality preservation)' do
    let(:tagged_yaml) do
      <<~YAML
        field: !custom_tag "value"
        normal: "regular_value"
      YAML
    end

    let(:temp_tagged_file) { create_temp_yaml_file(tagged_yaml) }

    after do
      FileUtils.rm_f(temp_tagged_file)
    end

    it 'preserves YAML tags in data structure' do
      result = described_class.load_yaml_with_tags(temp_tagged_file)

      expect(result['field']).to be_a(Hash)
      expect(result['field']['__tag__']).to eq('custom_tag')
      expect(result['field']['value']).to eq('value')
      expect(result['normal']).to eq('regular_value')
    end
  end
end

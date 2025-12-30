# frozen_string_literal: true

require_relative '../spec_helper'
require 'schemagraphy/attribute_resolver'

RSpec.describe SchemaGraphy::AttributeResolver do
  describe '.resolve_attributes! (internal implementation)' do
    let(:schema_with_attrs) do
      {
        'properties' => {
          'field1' => {
            'dflt' => '{test_attr}',
            'type' => 'String'
          },
          'field2' => {
            'properties' => {
              'nested' => {
                'dflt' => '{nested_attr}'
              }
            }
          },
          'field3' => {
            'dflt' => 'literal_value'
          }
        }
      }
    end

    let(:test_attrs) do
      {
        'test_attr' => 'resolved_value',
        'nested_attr' => 'nested_resolved'
      }
    end

    it 'mutates schema in place resolving dflt attribute references' do
      schema_with_attrs.dup
      result = described_class.resolve_attributes!(schema_with_attrs, test_attrs)

      # Returns the same object (mutated)
      expect(result).to be(schema_with_attrs)

      # Values are resolved
      expect(result.dig('properties', 'field1', 'dflt')).to eq('resolved_value')
      expect(result.dig('properties', 'field2', 'properties', 'nested', 'dflt')).to eq('nested_resolved')
      expect(result.dig('properties', 'field3', 'dflt')).to eq('literal_value')

      # Non-dflt fields unchanged
      expect(result.dig('properties', 'field1', 'type')).to eq('String')
    end

    it 'preserves unmatched attribute references' do
      result = described_class.resolve_attributes!(schema_with_attrs, {})

      expect(result.dig('properties', 'field1', 'dflt')).to eq('{test_attr}')
      expect(result.dig('properties', 'field2', 'properties', 'nested', 'dflt')).to eq('{nested_attr}')
    end

    it 'handles empty schema gracefully' do
      empty_schema = {}
      result = described_class.resolve_attributes!(empty_schema, test_attrs)
      expect(result).to eq({})
    end
  end

  describe '.resolve_attribute_reference (helper method)' do
    let(:attrs) { { 'test' => 'resolved', 'other' => 'other_value' } }

    it 'resolves single attribute reference' do
      result = described_class.resolve_attribute_reference('{test}', attrs)
      expect(result).to eq('resolved')
    end

    it 'resolves multiple attribute references' do
      result = described_class.resolve_attribute_reference('{test} and {other}', attrs)
      expect(result).to eq('resolved and other_value')
    end

    it 'preserves unmatched references' do
      result = described_class.resolve_attribute_reference('{missing}', attrs)
      expect(result).to eq('{missing}')
    end

    it 'handles mixed matched and unmatched references' do
      result = described_class.resolve_attribute_reference('{test} and {missing}', attrs)
      expect(result).to eq('resolved and {missing}')
    end

    it 'passes through strings without attribute references' do
      result = described_class.resolve_attribute_reference('literal string', attrs)
      expect(result).to eq('literal string')
    end
  end
end

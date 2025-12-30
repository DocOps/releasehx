# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe SchemaGraphy::CFGYML::PathReference do
  let(:data) do
    {
      'origin' => { 'source' => 'jira' },
      'items' => ['zero', { 'name' => 'example' }]
    }
  end

  describe '.load' do
    it 'loads JSON data from disk' do
      path = create_temp_json_file(data)

      reference = described_class.load(path)

      expect(reference.get('/origin/source')).to eq('jira')
    end
  end

  describe '#get' do
    let(:reference) { described_class.new(data) }

    it 'returns the root for an empty pointer' do
      expect(reference.get('')).to eq(data)
    end

    it 'resolves nested object pointers' do
      expect(reference.get('/origin/source')).to eq('jira')
    end

    it 'resolves array pointers' do
      expect(reference.get('/items/1/name')).to eq('example')
    end

    it 'raises for missing pointers' do
      expect { reference.get('/missing') }.to raise_error(KeyError)
    end
  end
end

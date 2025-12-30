# frozen_string_literal: true

require_relative 'spec_helper'
require 'releasehx/rhyml'

RSpec.describe ReleaseHx::RHYML do
  describe 'module structure' do
    it 'loads without errors' do
      expect { described_class }.not_to raise_error
    end
  end

  # Tests for RHYML submodules would go here
  describe 'submodules' do
    it 'has access to Adapter' do
      expect(defined?(ReleaseHx::RHYML::Adapter)).not_to be_nil
    end

    it 'has access to Change' do
      expect(defined?(ReleaseHx::RHYML::Change)).not_to be_nil
    end

    it 'has access to RHYMLFilters (Liquid)' do
      expect(defined?(ReleaseHx::RHYML::RHYMLFilters)).not_to be_nil
    end

    it 'has access to Loader classes' do
      expect(defined?(ReleaseHx::RHYML::Loader)).not_to be_nil
      expect(defined?(ReleaseHx::RHYML::MappingLoader)).not_to be_nil
      expect(defined?(ReleaseHx::RHYML::ReleaseLoader)).not_to be_nil
    end

    it 'has access to Release' do
      expect(defined?(ReleaseHx::RHYML::Release)).not_to be_nil
    end
  end

  # Test individual RHYML components
  describe 'RHYML Components' do
    let(:sample_data) { sample_rhyml_content }

    describe 'data handling' do
      it 'processes sample RHYML data structure' do
        expect(sample_data).to have_key('project')
        expect(sample_data).to have_key('version')
        expect(sample_data).to have_key('changes')
      end

      it 'validates RHYML structure' do
        changes = sample_data['changes']
        expect(changes).to be_an(Array)
        expect(changes.first).to have_key('type')
        expect(changes.first).to have_key('title')
      end
    end
  end
end

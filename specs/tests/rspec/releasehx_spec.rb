# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe ReleaseHx do
  it 'has a version number' do
    expect(ReleaseHx::VERSION).not_to be_nil
  end

  describe '.logger' do
    it 'returns a Logger instance' do
      expect(described_class.logger).to be_a(Logger)
    end

    it 'has a custom DUMP level' do
      expect(ReleaseHx::DUMP).to eq(Logger::DEBUG - 1)
    end

    it 'responds to dump method' do
      expect(described_class.logger).to respond_to(:dump)
    end
  end

  describe '.attrs' do
    context 'when RELEASEHX_DEV_RELOAD is not set' do
      it 'returns pre-generated attributes' do
        # This tests the runtime behavior
        ENV['RELEASEHX_DEV_RELOAD'] = nil
        expect { described_class.attrs }.not_to raise_error
      end
    end
  end

  describe 'Error' do
    it 'is a StandardError subclass' do
      expect(ReleaseHx::Error).to be < StandardError
    end
  end
end

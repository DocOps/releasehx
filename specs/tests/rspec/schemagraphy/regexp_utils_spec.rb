# frozen_string_literal: true

require_relative '../spec_helper'
require 'schemagraphy'

RSpec.describe SchemaGraphy::RegexpUtils do
  describe '.parse_pattern' do
    context 'with nil or empty input' do
      it 'returns nil for nil input' do
        expect(described_class.parse_pattern(nil)).to be_nil
      end

      it 'returns nil for empty string' do
        expect(described_class.parse_pattern('')).to be_nil
      end
    end

    context 'with regexp literal format' do
      it 'parses pattern and flags' do
        result = described_class.parse_pattern('/^hello.*$/im')
        expect(result[:pattern]).to eq('^hello.*$')
        expect(result[:flags]).to eq('im')
        expect(result[:regexp]).to be_a(Regexp)
      end

      it 'handles %r{} syntax' do
        result = described_class.parse_pattern('%r{^hello.*$}im')
        expect(result[:pattern]).to eq('^hello.*$')
        expect(result[:flags]).to eq('im')
        expect(result[:regexp]).to be_a(Regexp)
      end
    end

    context 'with plain pattern string' do
      it 'applies default flags when provided' do
        result = described_class.parse_pattern('hello.*world', 'im')
        expect(result[:pattern]).to eq('hello.*world')
        expect(result[:flags]).to eq('im')
        expect(result[:regexp].options & Regexp::IGNORECASE).to be_positive
        expect(result[:regexp].options & Regexp::MULTILINE).to be_positive
      end

      it 'handles empty flags' do
        result = described_class.parse_pattern('hello.*world')
        expect(result[:pattern]).to eq('hello.*world')
        expect(result[:flags]).to eq('')
        expect(result[:regexp].options).to eq(0)
      end
    end
  end

  describe '.extract_capture' do
    let(:sample_note) { "## Release Notes\nTest content\n## Other" }
    let(:sample_head) { "## Important Update\nContent here" }

    context 'with plain pattern string and explicit flags' do
      it 'extracts note content with default flags' do
        pattern_info = described_class.parse_pattern(
          '^## Release Notes\n(?<note>.*?)(?=\n##|\z)',
          'm')
        result = described_class.extract_capture(sample_note, pattern_info, 'note')
        expect(result).to eq('Test content')
      end

      it 'extracts heading with default flags' do
        pattern_info = described_class.parse_pattern(
          '^## (?<head>.*?)$',
          'm')
        result = described_class.extract_capture(sample_head, pattern_info, 'head')
        expect(result).to eq('Important Update')
      end
    end

    context 'with named and unnamed captures' do
      it 'prefers named capture when available' do
        pattern_info = described_class.parse_pattern('/^## (?<head>.*)$/')
        result = described_class.extract_capture(sample_head, pattern_info, 'head')
        expect(result).to eq('Important Update')
      end

      it 'falls back to first capture group when no name matches' do
        pattern_info = described_class.parse_pattern('/^## +(.+?)$/m')
        result = described_class.extract_capture(sample_head, pattern_info)
        expect(result).to eq('Important Update')
      end

      it 'returns full match when no captures exist' do
        pattern_info = described_class.parse_pattern('/^##.+$/')
        result = described_class.extract_capture(sample_head, pattern_info)
        expect(result).to eq('## Important Update')
      end
    end

    context 'with no matches' do
      it 'returns nil when pattern does not match' do
        pattern_info = described_class.parse_pattern('/no match/m')
        result = described_class.extract_capture(sample_note, pattern_info)
        expect(result).to be_nil
      end

      it 'returns nil for nil inputs' do
        pattern_info = described_class.parse_pattern('/test/m')
        expect(described_class.extract_capture(nil, pattern_info)).to be_nil
        expect(described_class.extract_capture('test', nil)).to be_nil
      end
    end
  end
end

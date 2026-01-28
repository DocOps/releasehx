# frozen_string_literal: true

require_relative '../spec_helper'
require 'releasehx/rhyml'

RSpec.describe ReleaseHx::RHYML::Adapter do
  let(:config) do
    {
      'conversions' => {
        'note' => 'issue_body',
        'note_pattern' => '/## Release Notes?\n(?m:(?<note>.*?))(?=\n##|\z)/',
        'head_source' => 'release_note_heading',
        'head_pattern' => '/^## (?<head>.*?)$/m'
      },
      'rhyml' => {
        'empty_notes' => 'skip',
        'empty_notes_content' => 'RELEASE NOTE NEEDED'
      },
      'tags' => {
        '_include' => ['highlight'],
        'release_note_needed' => {
          'slug' => 'needs-note'
        }
      }
    }
  end

  let(:mapping) do
    {
      'changes_array_path' => '@',
'note_pattern' => '/## Release Notes?\n(?<note>.*?)(?=\n##|\z)/ms',
      'head_pattern' => '/^## (?<head>.*?)$/m'
    }
  end

  let(:adapter) { described_class.new(mapping: mapping, config: config) }

  describe '#postprocess' do
    let(:data) do
      {
        'note' => "## Release Notes\nThis is a test note\n## Another Section\nIgnore this",
        'tags' => %w[needs-note highlight],
        'raw' => { 'labels' => ['needs-note'] }
      }
    end

    it 'extracts notes correctly' do
      processed = adapter.send(:postprocess, data.dup)
      expect(processed['note']).to eq('This is a test note')
    end

    it 'extracts head from note content' do
      data['note'] = "## Important Change\nThis is the content"
      processed = adapter.send(:postprocess, data.dup)
      expect(processed['head']).to eq('Important Change')
      expect(processed['note']).to eq('This is the content')
    end

    it 'processes tags' do
      processed = adapter.send(:postprocess, data.dup)
      expect(processed['tags']).to include('release_note_needed')
    end

    it 'handles missing notes based on policy' do
      data['note'] = nil
      processed = adapter.send(:postprocess, data.dup)
      # With 'skip' policy and release_note_needed tag, should return nil
      expect(processed).to be_nil
    end

    it 'adds placeholder note when configured' do
      config['rhyml']['empty_notes'] = 'empty'
      data['note'] = nil
      processed = adapter.send(:postprocess, data.dup)
      expect(processed['note']).to eq('RELEASE NOTE NEEDED')
    end
  end

  describe '#extract_note!' do
    let(:sample_note) { "## Release Notes\nTest content\n## Other" }
    let(:expected_content) { 'Test content' }

    shared_examples 'extracts note content' do |pattern_format|
      it "extracts note using #{pattern_format} pattern format" do
        data = { 'note' => sample_note }
        adapter.send(:extract_note!, data, 'issue_body', pattern)
        expect(data['note']).to eq(expected_content)
      end
    end

    context 'with /pattern/flags format' do
      let(:pattern) { '/## Release Notes\n(?m:(?<note>.*?))(?=\n##|\z)/' }

      it_behaves_like 'extracts note content', '/pattern/flags'
    end

    context 'with %r{} syntax' do
      let(:pattern) { '%r{## Release Notes\n(?m:(?<note>.*?))(?=\n##|\z)}' }

      it_behaves_like 'extracts note content', '%r{}'
    end

    it 'handles invalid patterns gracefully' do
      data = { 'note' => "## Release Notes\nTest content" }
      adapter.send(:extract_note!, data, 'issue_body', '(invalid pattern')
      # Should leave note unchanged on pattern error
      expect(data['note']).to eq("## Release Notes\nTest content")
    end
  end

  describe '#extract_head!' do
    let(:sample_note) { "## Important Update\nDetails here" }
    let(:expected_head) { 'Important Update' }
    let(:expected_note) { 'Details here' }

    shared_examples 'extracts heading' do |pattern_format|
      it "extracts heading using #{pattern_format} pattern format" do
        data = { 'note' => sample_note }
        adapter.send(:extract_head!, data, 'release_note_heading', pattern)
        expect(data['head']).to eq(expected_head)
        expect(data['note']).to eq(expected_note)
      end
    end

    context 'with /pattern/flags format' do
      let(:pattern) { '/^## (?<head>.*?)$/m' }

      it_behaves_like 'extracts heading', '/pattern/flags'
    end

    context 'with %r{} syntax' do
      let(:pattern) { '%r{^## (?<head>.*?)$}m' }

      it_behaves_like 'extracts heading', '%r{}'
    end

    context 'with unnamed capture groups' do
      let(:pattern) { '/^# +((.+?)\s*)$/m' } # Double capture to test first-group preference

      it 'uses first capture group' do
        data = { 'note' => "# No Named Group\nContent" }
        adapter.send(:extract_head!, data, 'release_note_heading', pattern)
        expect(data['head']).to eq('No Named Group')
        expect(data['note']).to eq('Content')
      end
    end
  end

  describe '#extract_raw_tags' do
    it 'extracts tags from raw labels' do
      data = { 'raw' => { 'labels' => [{ 'name' => 'bug' }, 'feature'] } }
      tags = adapter.send(:extract_raw_tags, data, ['original'])
      expect(tags).to contain_exactly('bug', 'feature')
    end

    it 'falls back to original tags' do
      data = { 'raw' => {} }
      tags = adapter.send(:extract_raw_tags, data, ['original'])
      expect(tags).to contain_exactly('original')
    end
  end
end

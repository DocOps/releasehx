# frozen_string_literal: true

require_relative 'spec_helper'
require 'sourcerer/jekyll'

RSpec.describe 'ReleaseHx Template System' do
  describe 'template loading and processing' do
    it 'loads Jekyll Liquid runtime without errors' do
      expect { Sourcerer::Jekyll.initialize_liquid_runtime }.not_to raise_error
    end

    it 'validates template system availability' do
      expect(defined?(Liquid)).not_to be_nil
      expect(defined?(Jekyll)).not_to be_nil
    end
  end

  describe 'template file existence' do
    let(:template_dir) { File.join(__dir__, '../../../lib/releasehx/rhyml/templates') }

    it 'has core HTML templates' do
      expect(File.exist?(File.join(template_dir, 'wrapper.html.liquid'))).to be true
      expect(File.exist?(File.join(template_dir, 'note.html.liquid'))).to be true
      expect(File.exist?(File.join(template_dir, 'entry.html.liquid'))).to be true
    end

    it 'has CSS templates' do
      expect(File.exist?(File.join(template_dir, 'embedded.css.liquid'))).to be true
    end

    it 'has core format templates' do
      expect(Dir.glob(File.join(template_dir, '*.liquid')).length).to be > 5
    end
  end

  describe 'CSS template features' do
    let(:css_template_path) { File.join(__dir__, '../../../lib/releasehx/rhyml/templates/embedded.css.liquid') }
    let(:css_content) { File.read(css_template_path) }

    it 'includes dark mode support' do
      expect(css_content).to include('@media (prefers-color-scheme: dark)')
    end

    it 'uses CSS custom properties' do
      expect(css_content).to include('--primary-color')
      expect(css_content).to include('--text-color')
    end

    it 'includes theme variables' do
      expect(css_content).to include('Theme: {{ theme }}')
    end
  end

  describe 'HTML template markup conversion' do
    let(:note_template_path) { File.join(__dir__, '../../../lib/releasehx/rhyml/templates/note.html.liquid') }
    let(:note_content) { File.read(note_template_path) }

    it 'uses markdownify filter for markdown content' do
      expect(note_content).to include('markdownify')
    end

    it 'uses asciidocify filter for asciidoc content' do
      expect(note_content).to include('asciidocify')
    end

    it 'handles different markup types conditionally' do
      expect(note_content).to include('config.conversions.markup == "markdown"')
      expect(note_content).to include('config.conversions.markup == "asciidoc"')
    end
  end

  describe 'Bootstrap integration' do
    let(:wrapper_template_path) { File.join(__dir__, '../../../lib/releasehx/rhyml/templates/wrapper.html.liquid') }
    let(:wrapper_content) { File.read(wrapper_template_path) }

    it 'includes Bootstrap CDN links when using Bootstrap framework' do
      expect(wrapper_content).to include('bootstrap@5.3.0')
    end

    it 'includes dark mode detection script' do
      expect(wrapper_content).to include('data-bs-theme')
      expect(wrapper_content).to include('prefers-color-scheme')
    end

    it 'listens for system theme changes' do
      expect(wrapper_content).to include('addEventListener')
    end
  end

  describe 'template processing with sample data' do
    let(:sample_change) do
      {
        'chid' => 'test-1',
        'note' => 'This is a **bold** note with `code`',
        'head' => 'Test Change'
      }
    end

    let(:sample_config) do
      {
        'conversions' => { 'markup' => 'markdown' }
      }
    end

    it 'validates basic template processing' do
      template_content = 'Release {{ version }} - {{ change.head }}'
      template = Liquid::Template.parse(template_content)
      result = template.render('change' => sample_change, 'version' => '1.0.0')

      expect(result).to eq('Release 1.0.0 - Test Change')
    end
  end

  describe 'template variables and context' do
    it 'validates template variable accessibility' do
      template_content = '{{ config.conversions.markup }}'
      template = Liquid::Template.parse(template_content)
      result = template.render('config' => { 'conversions' => { 'markup' => 'markdown' } })
      expect(result).to eq('markdown')
    end

    it 'handles nested template structures' do
      template_content = '{% for change in changes %}{{ change.chid }}{% endfor %}'
      template = Liquid::Template.parse(template_content)
      changes = [{ 'chid' => 'test-1' }, { 'chid' => 'test-2' }]
      result = template.render('changes' => changes)
      expect(result).to eq('test-1test-2')
    end
  end
end

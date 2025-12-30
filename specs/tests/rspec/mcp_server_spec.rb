# frozen_string_literal: true

require_relative 'spec_helper'
require 'fileutils'
require 'releasehx/mcp'

RSpec.describe ReleaseHx::MCP::Server do
  let(:tmp_dir) { Dir.mktmpdir('releasehx_mcp_spec_') }
  let(:asset_root) { File.join(tmp_dir, 'assets') }
  let(:source_root) { File.join(tmp_dir, 'source') }

  let(:manifest_data) do
    {
      resources: [
        {
          href: 'releasehx://agent/guide',
          name: 'agent-guide',
          desc: 'Agent guide for ReleaseHx configuration discovery',
          mime: 'text/markdown',
          path: File.join(source_root, 'agent-config-guide.md'),
          file: 'agent-config-guide.md'
        },
        {
          href: 'releasehx://config/sample',
          name: 'config-sample',
          desc: 'Sample config tree with defaults and comments',
          mime: 'text/yaml',
          path: File.join(source_root, 'sample-config.yml'),
          file: 'sample-config.yml'
        },
        {
          href: 'releasehx://config/schema',
          name: 'config-schema',
          desc: 'Authoritative configuration definition (CFGYML)',
          mime: 'text/yaml',
          path: File.join(source_root, 'config-def.yml'),
          file: 'config-def.yml'
        },
        {
          href: 'releasehx://config/reference.json',
          name: 'config-reference-json',
          desc: 'JSON reference document for configuration settings',
          mime: 'application/json',
          path: File.join(source_root, 'config-reference.json'),
          file: 'config-reference.json'
        },
        {
          href: 'releasehx://config/reference.adoc',
          name: 'config-reference-adoc',
          desc: 'AsciiDoc configuration reference',
          mime: 'text/asciidoc',
          path: File.join(source_root, 'config-reference.adoc'),
          file: 'config-reference.adoc'
        }
      ],
      tools: [
        {
          name: 'config.reference.get',
          title: 'Config Reference Lookup',
          desc: 'Retrieve config reference details using JSON Pointer',
          input_schema: {
            type: 'object',
            properties: {
              pointer: {
                type: 'string',
                desc: 'JSON Pointer string for the reference JSON'
              }
            },
            required: ['pointer']
          },
          annotations: {
            title: 'Config Reference Lookup',
            read_only_hint: true,
            destructive_hint: false,
            idempotent_hint: true,
            open_world_hint: false
          }
        }
      ]
    }
  end

  let(:manifest) { ReleaseHx::MCP::Manifest.new(manifest_data) }
  let(:resource_pack) { ReleaseHx::MCP::ResourcePack.new(manifest: manifest, asset_root: asset_root) }
  let(:server) { described_class.new(manifest: manifest, resource_pack: resource_pack) }

  before do
    FileUtils.mkdir_p(source_root)
    FileUtils.mkdir_p(asset_root)
    File.write(File.join(source_root, 'agent-config-guide.md'), '# MCP Agent Guide')
    File.write(File.join(source_root, 'sample-config.yml'), "origin:\n  source: jira\n")
    File.write(File.join(source_root, 'config-def.yml'), "properties:\n  origin:\n    type: Map\n")
    File.write(File.join(source_root, 'config-reference.json'), JSON.generate({ 'origin' => { 'source' => 'jira' } }))
    File.write(File.join(source_root, 'config-reference.adoc'), '= Config Reference')
    ReleaseHx::MCP::AssetPackager.new(manifest: manifest, asset_root: asset_root).package!
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe 'resources' do
    it 'lists available resources' do
      resources = server.list_resources

      expect(resources).to include('releasehx://agent/guide')
      expect(resources).to include('releasehx://config/sample')
      expect(resources).to include('releasehx://config/schema')
      expect(resources).to include('releasehx://config/reference.json')
      expect(resources).to include('releasehx://config/reference.adoc')
    end

    it 'retrieves resource contents' do
      expect(server.get_resource('releasehx://agent/guide')).to include('MCP Agent Guide')
      expect(server.get_resource('releasehx://config/sample')).to include('origin:')
      expect(server.get_resource('releasehx://config/schema')).to include('properties:')
      expect(server.get_resource('releasehx://config/reference.json')).to include('"origin"')
      expect(server.get_resource('releasehx://config/reference.adoc')).to include('Config Reference')
    end

    it 'raises when a packaged resource is missing' do
      FileUtils.rm_f(File.join(asset_root, 'sample-config.yml'))

      expect { server.get_resource('releasehx://config/sample') }
        .to raise_error(Errno::ENOENT, /Missing MCP resource file/)
    end
  end

  describe 'tools' do
    it 'returns reference data for config.reference.get' do
      response = server.send(:handle_tool, 'config.reference.get', { pointer: '/origin' }, nil)

      expect(response).to be_a(MCP::Tool::Response)
      expect(response.structured_content).to eq({ 'source' => 'jira' })
    end

    it 'returns an error response for missing pointers' do
      response = server.send(:handle_tool, 'config.reference.get', { pointer: '/missing' }, nil)

      expect(response).to be_a(MCP::Tool::Response)
      expect(response.error?).to be(true)
    end
  end
end

RSpec.describe ReleaseHx::MCP::AssetPackager do
  let(:tmp_dir) { Dir.mktmpdir('releasehx_mcp_packager_spec_') }
  let(:asset_root) { File.join(tmp_dir, 'assets') }
  let(:source_root) { File.join(tmp_dir, 'source') }

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  it 'raises when a source file is missing' do
    manifest = ReleaseHx::MCP::Manifest.new(
      {
        resources: [
          {
            href: 'releasehx://agent/guide',
            name: 'agent-guide',
            desc: 'Agent guide for ReleaseHx configuration discovery',
            mime: 'text/markdown',
            path: File.join(source_root, 'agent-config-guide.md'),
            file: 'agent-config-guide.md'
          }
        ],
            tools: []
      })

    expect { described_class.new(manifest: manifest, asset_root: asset_root).package! }
      .to raise_error(Errno::ENOENT, /Missing MCP resource source/)
  end
end

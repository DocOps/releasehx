# frozen_string_literal: true

begin
  require_relative 'lib/releasehx/generated'
rescue LoadError
  warn 'WARNING: Generated metadata file missing. Run `rake prebuild` first.'
  module ReleaseHx
    ATTRIBUTES = { globals: {} }.freeze
  end
end

attrs = ReleaseHx::ATTRIBUTES[:globals]

Gem::Specification.new do |spec|
  spec.name          = 'releasehx'
  spec.version       = attrs['this_prod_vrsn'] || '0.0.0-alpha'
  spec.authors       = ['DocOpsLab']
  spec.email         = ['docopslab@protonmail.com']

  spec.summary       = attrs['tagline'] || 'No summary available'
  spec.description   = attrs['description'] || 'No description available'
  spec.homepage      = 'https://github.com/DocOPs/releasehx'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir['lib/**/*.rb'] +
               Dir['lib/templates/*'] +
               Dir['lib/releasehx/rhyml/templates/*'] +
               Dir['bin/*'] +
               Dir['lib/releasehx/mappings/*'] +
               Dir['lib/releasehx/rest/clients/*.yml'] +
               Dir['lib/releasehx/rhyml/mappings/*.{yml,yaml}'] +
               Dir['lib/releasehx/mcp/assets/*'] +
               ['README.adoc'] +
               Dir['specs/data/*'] +
               Dir['build/snippets/*.txt'] +
               Dir['build/docs/*']

  spec.bindir        = 'bin'
  spec.executables   = %w[releasehx rhx rhx-mcp]
  spec.require_paths = ['lib']

  # Development dependencies are in Gemfile per RuboCop best practices

  spec.add_dependency 'faraday', '~> 2.9'
  spec.add_dependency 'faraday-follow_redirects', '~> 0.3.0'
  spec.add_dependency 'thor', '~> 1.3'

  spec.add_dependency 'jmespath', '~> 1.6'
  spec.add_dependency 'jsonpath', '~> 1.1'
  spec.add_dependency 'tilt', '~> 2.3'
  spec.add_dependency 'yaml', '~> 0.4'

  spec.add_dependency 'asciidoctor-pdf', '~> 2.3'
  spec.add_dependency 'commonmarker', '~> 0.23'
  spec.add_dependency 'jekyll', '~> 4.4'
  spec.add_dependency 'jekyll-asciidoc', '~> 3.0.0'
  spec.add_dependency 'kramdown', '~> 2.4'
  spec.add_dependency 'kramdown-asciidoc', '~> 2.1'
  spec.add_dependency 'liquid', '~> 4.0'
  spec.add_dependency 'mcp', '~> 0.4'
  spec.add_dependency 'prism', '~> 1.5'
  spec.add_dependency 'to_regexp', '= 0.2.1'
end

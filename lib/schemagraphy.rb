# frozen_string_literal: true

require_relative 'schemagraphy/loader'
require_relative 'schemagraphy/tag_utils'
require_relative 'schemagraphy/schema_utils'
require_relative 'schemagraphy/templating'
require_relative 'schemagraphy/regexp_utils'
require_relative 'schemagraphy/cfgyml/doc_builder'
require_relative 'schemagraphy/data_query/json_pointer'
require_relative 'schemagraphy/cfgyml/path_reference'

# SchemaGraphy is a component for working with schema-driven data structures and extending YAML with robust typing and dynamic directives.
# It provides utilities for loading, validating, and transforming data based on
# a schema definition, with a focus on templating and safe expression evaluation.
# This module is under early development and will be spun off as its own gem after ReleaseHx is generally available.
module SchemaGraphy
end

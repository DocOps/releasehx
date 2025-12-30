# frozen_string_literal: true

require 'prism'
require 'timeout'

module SchemaGraphy
  # Provides a simple, deny-by-exception sandbox for mapping expressions.
  # It validates code by walking the Abstract Syntax Tree (AST) and blocking
  # known dangerous operations, rather than attempting to allowlist safe ones.
  class AstGate
    # A list of dangerous bareword methods that are blocked.
    BLOCKED_BAREWORDS = %w[
      eval instance_eval class_eval module_eval binding
      require require_relative load autoload
      system exec spawn fork backtick `
      open ObjectSpace GC Thread Process at_exit
    ].freeze

    # A list of AST node types that are explicitly disallowed.
    DISALLOWED_NODES = %i[
      # Definitions and meta-programming
      def_node class_node module_node define_node alias_node undef_node
      # Globals and constants paths
      global_variable_read_node constant_path_node
      # Shell and backticks
      x_string_node interpolated_x_string_node
    ].freeze

    # A list of constants that are considered dangerous and are blocked.
    DANGEROUS_CONSTANTS = %w[
      Kernel Object Module Class File FileUtils IO Dir Process Open3 PTY Thread
      SystemSignal Signal Gem Net HTTP TCPSocket UDPSocket Socket ObjectSpace GC
    ].freeze

    # Validates the given code by parsing it and walking the AST.
    #
    # @param code [String] The Ruby code to validate.
    # @param context_keys [Array<Symbol>] A list of keys available in the execution context.
    # @raise [SyntaxError] if the code has syntax errors.
    # @raise [SecurityError] if the code contains disallowed operations.
    def self.validate! code, context_keys: []
      result = Prism.parse(code)
      raise SyntaxError, result.errors.map(&:message).join(', ') if result.errors.any?

      walk(result.value, context_keys: context_keys)
    end

    # @api private
    # Recursively walks the AST, checking for disallowed nodes and operations.
    #
    # @param node [Prism::Node] The current AST node.
    # @param context_keys [Array<Symbol>] A list of keys available in the execution context.
    # @raise [SecurityError] if a disallowed operation is found.
    def self.walk node, context_keys: []
      return unless node.is_a?(Prism::Node)

      type = node.type
      raise SecurityError, "node not allowed: #{type}" if DISALLOWED_NODES.include?(type)

      case node
      when Prism::CallNode
        # Block dangerous barewords (system, eval, etc.)
        if node.receiver.nil? && BLOCKED_BAREWORDS.include?(node.name.to_s)
          raise SecurityError, "method not allowed: #{node.name}"
        end
        # Block dangerous constants and constant paths
        if node.receiver.is_a?(Prism::ConstantReadNode) && DANGEROUS_CONSTANTS.include?(node.receiver.name.to_s)
          raise SecurityError, "unsafe constant: #{node.receiver.name}"
        end
        raise SecurityError, 'unsafe constant path' if node.receiver.is_a?(Prism::ConstantPathNode)

      when Prism::ConstantReadNode
        # Allow only core Ruby constants defined in SafeTransform
        const_name = node.name.to_s
        unless SafeTransform::CORE_CONSTANTS.key?(const_name.to_sym)
          raise SecurityError, "constant not allowed: #{const_name}"
        end
      when Prism::ConstantPathNode, Prism::GlobalVariableReadNode
        raise SecurityError, 'constant paths and global variables are not allowed'
      when Prism::DefNode, Prism::ClassNode, Prism::ModuleNode
        raise SecurityError, 'method, class, and module definitions are not allowed'
      when Prism::BackReferenceReadNode, Prism::XStringNode, Prism::InterpolatedXStringNode
        raise SecurityError, 'shell commands and backticks are not allowed'
      end

      node.child_nodes.each { |child| walk(child, context_keys: context_keys) if child }
    end
  end

  # Provides a sandboxed environment for executing Ruby code.
  # Inherits from `BasicObject` for a minimal namespace and uses `instance_eval`
  # to run code within its own context. All code is validated by {AstGate} before execution.
  class SafeTransform < BasicObject
    # A minimal set of core Ruby constants exposed to the sandboxed environment.
    CORE_CONSTANTS = {
      Array:      ::Array,
      Hash:       ::Hash,
      String:     ::String,
      Integer:    ::Integer,
      Float:      ::Float,
      TrueClass:  ::TrueClass,
      FalseClass: ::FalseClass,
      NilClass:   ::NilClass,
      Symbol:     ::Symbol,
      Numeric:    ::Numeric,
      Regexp:     ::Regexp
    }.freeze

    CORE_CONSTANTS.each do |name, ref|
      const_set(name, ref) unless const_defined?(name, false)
    end

    # @param context [Hash] A hash of data to be made available in the sandbox.
    def initialize context = {}
      @context = context
    end

    # Executes the given code within the sandboxed environment.
    #
    # @param code [String] The Ruby code to execute.
    # @return [Object] The result of the executed code.
    # @raise [Timeout::Error] if the execution time exceeds the limit.
    # @raise [SecurityError] if the code contains disallowed operations.
    def transform code
      ::Timeout.timeout(0.25) do
        AstGate.validate!(code, context_keys: @context.keys)
        instance_eval(code)
      end
    rescue ::Timeout::Error
      ::Kernel.raise ::StandardError, 'transform timed out'
    end

    # Adds a key-value pair to the execution context.
    #
    # @param key [String, Symbol] The key to add.
    # @param value [Object] The value to associate with the key.
    def add_context key, value
      @context[key.to_s] = value
    end

    # Safely traverses a nested object using a dot-separated path.
    #
    # @param obj [Object] The object to traverse.
    # @param path [String] The dot-separated path (e.g., "a.b.c").
    # @return [Object, nil] The value at the specified path, or `nil`.
    def dig_path obj, path
      keys = path.to_s.split('.')
      keys.reduce(obj) { |memo, key| memo.respond_to?(:[]) ? memo[key] : nil }
    end

    def to_s
      '#<SchemaGraphy::SafeTransform>'
    end

    private

    # Handles access to variables in the context.
    def method_missing(name, *args, &block)
      key = name.to_s
      if @context.key?(key) && args.empty? && block.nil?
        @context[key]
      else
        ::Kernel.raise ::NoMethodError, "undefined method `#{name}` for #{self}"
      end
    end

    def respond_to_missing? name, include_private = false
      @context.key?(name.to_s) || super
    end

    # Disable methods that could be used to break out of the sandbox.

    def instance_exec(*_args)
      ::Kernel.raise ::NoMethodError, 'disabled'
    end

    def method(*_args)
      ::Kernel.raise ::NoMethodError, 'disabled'
    end

    def singleton_class(*_args)
      ::Kernel.raise ::NoMethodError, 'disabled'
    end

    def define_singleton_method(*_args)
      ::Kernel.raise ::NoMethodError, 'disabled'
    end
  end
end

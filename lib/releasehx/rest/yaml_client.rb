# frozen_string_literal: true

require 'yaml'
require 'faraday'
require 'base64'
require 'liquid'
require 'erb'
require 'fileutils'
require 'digest'

module ReleaseHx
  module REST
    class YamlClient
      attr_reader :raw_response

      def initialize config, version = nil
        @version = version
        @config = config
        @origin_cfg = config['origin'] || {}
        @origin_source = @origin_cfg['source']
        @vars = build_scope
        @client_def = load_render_client_def
        @resolved_values = {}
        @cache_config = config.dig('paths', 'cache') || {}
        @raw_response = nil
        normalize_fields!
        setup_connection
        perform_resolutions!
      end

      def fetch_all
        # Check for cached response first (unless force fetch is requested)
        if cache_enabled? && !force_fetch_requested? && (cached_data = cached_response)
          ReleaseHx.logger.info "Using cached API response (#{cached_data.size} items) from #{@origin_source}"
          return cached_data
        end

        # Fetch fresh data from API
        results = fetch_fresh_data

        # Save to cache if caching is enabled
        save_to_cache(results) if cache_enabled?

        ReleaseHx.logger.info "Fetched #{results.size} items from #{@origin_source} API"
        results
      end

      def fetch_fresh_data
        results = []

        if pagination?
          page_param     = pagination['param']
          page_size_key  = pagination['page_size_param']
          page_size_val  = pagination['page_size']

          current_index = 0
          loop_count = 0
          max_pages = pagination['max_pages'] || 100

          loop do
            query = query_params.merge(
              {
                page_param => current_index,
                            page_size_key => page_size_val
              })

            # Report to logger debug the API URL and query params
            ReleaseHx.logger.debug "Fetching from: #{@href} with query: #{query.inspect}"

            resp = @conn.get(@href, query, @headers)
            body = resp.body
            raise "HTTP Error #{resp.status}" unless resp.success?

            # Save raw response from first page for payload export
            @raw_response = body if loop_count.zero?

            issues = extract_issues_from_response(body)
            results.concat(Array(issues))

            break if issues.nil? || issues.size.to_i < page_size_val

            current_index += page_size_val
            loop_count += 1
            break if loop_count >= max_pages
          end
        else
          resp = @conn.get(@href, query_params, @headers)
          raise "HTTP Error #{resp.status}" unless resp.success?

          # Save raw response before extraction
          @raw_response = resp.body

          issues = extract_issues_from_response(resp.body)
          results = Array(issues)
        end

        results
      end

      private

      def extract_issues_from_response body
        root_path = @client_def['root_issues_path']
        if root_path && !root_path.empty? && root_path != '.'
          body[root_path]
        else
          body
        end
      end

      def build_scope
        {
          'origin' => @origin_cfg.merge('version' => @version),
          'env' => ENV.to_h
        }
      end

      def load_render_client_def
        user_dir = @config.dig('paths', 'api_clients_dir') || '_apis'
        user_file = File.join(user_dir, "#{@origin_source}.yaml")
        builtin_file = File.expand_path("clients/#{@origin_source}.yml", __dir__)
        path = File.exist?(user_file) ? user_file : builtin_file
        raise "Missing client config for API: #{@origin_source}" unless File.exist?(path)

        raw = File.read(path)
        # Load raw YAML first, then selectively render templated fields
        YAML.safe_load(raw)
      end

      def normalize_fields!
        @href     = @origin_cfg['href'] || render_field(@client_def['href'])
        # Use client auth if main config auth is incomplete (missing mode/header/format)
        main_auth = @origin_cfg['auth'] || {}
        client_auth = @client_def['auth'] || {}
        has_required = main_auth['mode'] && main_auth['header'] && (main_auth['format'] || main_auth['key_env'])
        @auth = has_required ? main_auth : client_auth
        @headers = build_headers
        @query_string = @origin_cfg['string'] || @client_def['query_string']
      end

      def pagination
        @origin_cfg['pagination'] || @client_def['pagination']
      end

      def pagination?
        !!pagination
      end

      def render_field val
        context = build_scope['origin'].merge('env' => build_scope['env'])
        render_if_templated(val, context)
      end

      def render_if_templated template_def, context
        return template_def unless template_def.is_a?(String) && template_def.include?('{{')

        # Use Liquid templating directly like RHYML adapter
        template = ::Liquid::Template.parse(template_def)
        template.render(context)
      rescue StandardError => e
        ReleaseHx.logger.error "Error rendering template '#{template_def}': #{e.message}"
        template_def # Return original on error
      end

      def build_headers
        return {} unless @auth['mode'] && @auth['header'] && @auth['format']

        value = render_field(@auth['format'])
        {
          @auth['header'] => value
        }
      end

      def query_params
        base = {}

        # Prefer structured query_params over legacy query_string
        if @client_def['query_params']
          # New structured approach
          query_type = @client_def['query_type'] || 'key_value'

          case query_type.to_s.downcase
          when 'jql'
            # Jira JQL; render the whole query_params as a single JQL string
            base['jql'] = render_structured_params(@client_def['query_params'])
          else
            # GitHub/GitLab style; render each param individually
            @client_def['query_params'].each do |key, value|
              base[key] = render_field_with_resolutions(value)
            end
          end
        elsif @query_string
          # Legacy query_string approach (backward compatibility)
          rendered_query = render_field_with_resolutions(@query_string)
          query_type = @client_def['query_type'] || detect_query_type(rendered_query)

          case query_type.to_s.downcase
          when 'jql'
            base['jql'] = rendered_query
          when 'key_value'
            base.merge!(parse_query_string_to_hash(rendered_query))
          when 'query_string'
            base['string'] = rendered_query
          else
            base.merge!(smart_parse_query_params(rendered_query))
          end
        end

        # Merge any additional params from config
        base.merge!(@origin_cfg['params'] || {})
        base
      end

      def detect_query_type query_str
        # Smart detection based on query string characteristics
        if query_str.include?('&') && query_str.include?('=')
          # Contains & and = - likely key_value format
          'key_value'
        elsif query_str.match?(/\b(AND|OR|IN|NOT|ORDER BY|WHERE)\b/i)
          # Contains SQL/JQL keywords; likely JQL
          'jql'
        else
          # Default to query_string for safety
          'query_string'
        end
      end

      def parse_query_string_to_hash query_str
        # Parse "key=value&key2=value2" into hash
        result = {}
        query_str.split('&').each do |pair|
          key, value = pair.split('=', 2)
          result[key] = value if key && value
        end
        result
      end

      def smart_parse_query_params query_str
        # Smart fallback parsing
        if query_str.include?('&') && query_str.include?('=')
          # Looks like key-value pairs
          parse_query_string_to_hash(query_str)
        elsif query_str.match?(/\b(AND|OR|IN|NOT)\b/i)
          # Single string; could be JQL or raw query
          # Looks like JQL
          { 'jql' => query_str }
        else
          # Raw query string
          { 'string' => query_str }
        end
      end

      def perform_resolutions!
        resolutions = @client_def['resolutions'] || {}
        return if resolutions.empty?

        ReleaseHx.logger.debug "Performing #{resolutions.keys.size} resolutions: #{resolutions.keys.join(', ')}"

        resolutions.each do |name, config|
          @resolved_values[name] = resolve_entity(config)
          ReleaseHx.logger.debug "Resolved #{name}: #{@resolved_values[name]}"
        end
      end

      def resolve_entity config
        # Build resolution endpoint URL with proper context
        context = build_scope['origin'].merge('env' => build_scope['env'])
        endpoint = render_if_templated(config['endpoint'], context)
        base_url = @href.split('/repos/').first # Extract base API URL
        resolution_url = "#{base_url}#{endpoint}"

        ReleaseHx.logger.debug "Resolving entity from: #{resolution_url}"

        # Fetch resolution data
        resp = @conn.get(resolution_url, {}, @headers)
        raise "Resolution HTTP Error #{resp.status} for #{endpoint}" unless resp.success?

        entities = Array(resp.body)
        match_value = render_if_templated(config['match_value'], context)
        lookup_field = config['lookup_field']
        return_field = config['return_field']

        ReleaseHx.logger.debug "Looking for #{lookup_field}='#{match_value}' in #{entities.size} entities"

        # Find matching entity
        matching_entity = entities.find { |entity| entity[lookup_field] == match_value }

        if matching_entity
          result = matching_entity[return_field]
          ReleaseHx.logger.debug "Found match: #{lookup_field}='#{match_value}' -> #{return_field}='#{result}'"
          result
        else
          available = entities.map { |e| e[lookup_field] }.compact.join(', ')
          raise "No entity found with #{lookup_field}='#{match_value}'. Available: #{available}"
        end
      end

      def render_field_with_resolutions val
        # Build context with resolved values for templating
        context = build_scope['origin'].merge('env' => build_scope['env']).merge(@resolved_values)
        ReleaseHx.logger.debug "Template context for '#{val}': #{context.keys} (resolved: #{@resolved_values})"
        result = render_if_templated(val, context)
        ReleaseHx.logger.debug "Template result: '#{result}'"
        result
      end

      def render_structured_params params_hash
        # For JQL; combine all params into a single query string
        rendered_parts = params_hash.map do |key, value|
          rendered_value = render_field_with_resolutions(value)
          "#{key}=#{rendered_value}"
        end
        rendered_parts.join(' AND ')
      end

      def setup_connection
        require 'faraday/follow_redirects'
        @conn = Faraday.new do |f|
          f.request :url_encoded
          f.response :json, parser_options: { symbolize_names: false }
          f.use Faraday::FollowRedirects::Middleware
          f.adapter Faraday.default_adapter
        end
      end

      # Cache management methods
      def cache_enabled?
        @cache_config['enabled']
      end

      def force_fetch_requested?
        # Check if CLI options force fresh fetch (--force or --fetch flags)
        # These are passed through the config under cli_flags
        @config.dig('cli_flags', 'force') || @config.dig('cli_flags', 'fetch')
      end

      def cache_dir
        @cache_config['dir']
      end

      def cache_ttl_hours
        @cache_config['ttl_hours']
      end

      def cache_file_path
        # Create structured cache path: cache_dir/api_from/version/payload.json
        version_part = @version || 'default'
        cache_subdir = File.join(cache_dir, @source_type, version_part)
        File.join(cache_subdir, 'payload.json')
      end

      def cached_response
        cache_path = cache_file_path
        return nil unless File.exist?(cache_path)

        # Check if cache is still valid (within TTL)
        cache_age_hours = (Time.now - File.mtime(cache_path)) / 3600.0
        if cache_age_hours > cache_ttl_hours
          ReleaseHx.logger.debug "Cache expired (#{cache_age_hours.round(1)}h old, TTL: #{cache_ttl_hours}h)"
          return nil
        end

        ReleaseHx.logger.debug "Using cache from #{cache_path} (#{cache_age_hours.round(1)}h old)"

        begin
          cached_content = File.read(cache_path)
          JSON.parse(cached_content)
        rescue StandardError => e
          ReleaseHx.logger.warn "Failed to read cache file #{cache_path}: #{e.message}"
          nil
        end
      end

      def save_to_cache api_response
        cache_path = cache_file_path
        cache_subdir = File.dirname(cache_path)

        begin
          # Create cache directory structure
          FileUtils.mkdir_p(cache_subdir)

          # Write API response to cache file
          File.write(cache_path, JSON.pretty_generate(api_response))
          ReleaseHx.logger.debug "Saved API response to cache: #{cache_path}"

          # Handle .gitignore if requested
          handle_gitignore_prompt if @cache_config['prompt_gitignore']
        rescue StandardError => e
          ReleaseHx.logger.warn "Failed to save cache to #{cache_path}: #{e.message}"
        end
      end

      def handle_gitignore_prompt
        gitignore_path = '.gitignore'
        cache_dir_pattern = "/#{cache_dir.gsub(%r{^\.?/}, '')}"

        # Check if .gitignore already contains our cache directory
        if File.exist?(gitignore_path)
          gitignore_content = File.read(gitignore_path)
          return if gitignore_content.include?(cache_dir_pattern)
        end

        # Prompt user to add cache directory to .gitignore
        # For now, we'll just add it automatically since we can't prompt in non-interactive mode
        begin
          File.open(gitignore_path, 'a') do |f|
            f.puts
            f.puts '# ReleaseHx API cache'
            f.puts cache_dir_pattern
          end
          ReleaseHx.logger.info "Added #{cache_dir_pattern} to .gitignore"
        rescue StandardError => e
          ReleaseHx.logger.warn "Could not update .gitignore: #{e.message}"
        end
      end
    end
  end
end

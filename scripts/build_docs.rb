# frozen_string_literal: true

require 'asciidoctor'
require 'yard'
require 'jekyll'
require 'pathname'
require 'nokogiri'
require 'fileutils'

module DocOpsLab
  module DocBuilder
    def self.build_docs version
      puts "Generating docs for version #{version}..."

      prepare_jekyll_source version
      generate_module_docs version
      add_jekyll_front_matter
      build_jekyll_site

      puts 'Docs generated in build/docs/_site'
      puts 'To serve locally, run: rake serve'
    end

    def self.prepare_jekyll_source _version
      puts 'Preparing Jekyll source directory...'

      raise 'README.adoc not found in current directory' unless File.exist?('README.adoc')

      raise 'docs/ directory not found' unless Dir.exist?('docs')

      FileUtils.mkdir_p 'build/docs'
      FileUtils.cp 'README.adoc', 'build/docs/index.adoc'
      FileUtils.cp_r 'docs/.', 'build/docs/'

      # Add front matter to config-reference.adoc
      add_config_reference_front_matter

      # Update version in Jekyll config
      config_path = 'build/docs/_config.yml'
      raise "Jekyll config not found at #{config_path}" unless File.exist?(config_path)

      config_content = File.read(config_path)
      File.write(config_path, config_content)
    end

    def self.add_config_reference_front_matter
      config_ref_path = 'build/docs/config-reference.adoc'
      return unless File.exist?(config_ref_path)

      content = File.read(config_ref_path)

      # Add front matter if not already present
      return if content.start_with?(':page-layout:')

      front_matter = <<~FRONT_MATTER
        :page-layout: default
        :page-permalink: /docs/config-reference/
        :page-nav_order: 2
        :page-redirect_from: ["/config-reference"]
        :page-title: Configuration Reference
      FRONT_MATTER

      File.write(config_ref_path, front_matter + content)
    end

    def self.generate_module_docs version
      puts 'Generating API docs with YARD...'

      mod = build_releasehx_module

      puts "--> Generating docs for #{mod[:name]}..."

      unless File.exist?(mod[:readme])
        puts "    Warning: README not found at #{mod[:readme]}, skipping"
        return
      end

      if mod[:files].empty?
        puts "    Warning: No Ruby files found for #{mod[:name]}, skipping"
        return
      end

      readme_dir = File.dirname(mod[:readme])
      readme_content = File.read(mod[:readme])
      processed_readme_html = Asciidoctor.convert(
        readme_content, safe: :unsafe, base_dir: readme_dir, header_footer: false)
      temp_readme_path = "build/docs/#{mod[:name].downcase}_readme.html"
      File.write(temp_readme_path, processed_readme_html)

      output_dir = "build/docs/docs/api/#{mod[:name].downcase}"
      FileUtils.mkdir_p output_dir
      file_list = mod[:files].join(' ')

      # Use custom YARD templates from docs/yard/templates
      template_dir = 'docs/yard/templates'
      custom_css = 'docs/yard/assets/css/custom.css'

      yard_cmd = "yard doc --output-dir #{output_dir} --readme #{temp_readme_path} " \
                 "--title \"#{mod[:name]} API (v#{version})\" --markup html " \
                 "--template-path #{template_dir}"

      # Add custom CSS if it exists
      yard_cmd += " --asset #{custom_css}:css/" if File.exist?(custom_css)

      yard_cmd += " #{file_list}"

      puts "    Warning: YARD generation failed for #{mod[:name]}" unless system(yard_cmd)

      # Post-process HTML files to add custom CSS with correct relative paths
      return unless File.exist?(custom_css)

      Dir.glob("#{output_dir}/**/*.html").each do |html_file|
        add_custom_css_to_html(html_file, output_dir)
      end

      # Fix YARD index file naming: _index.html is the real API index,
      # but index.html is generated from README. Rename them appropriately.
      yard_index = File.join(output_dir, '_index.html')
      readme_index = File.join(output_dir, 'index.html')

      return unless File.exist?(yard_index)

      # Rename README-based index to readme.html
      File.rename(readme_index, File.join(output_dir, 'readme.html')) if File.exist?(readme_index)
      # Rename _index.html to index.html (this is the real API overview)
      File.rename(yard_index, readme_index)
    end

    def self.add_custom_css_to_html html_file, base_output_dir
      content = File.read(html_file)

      # Calculate relative path from this HTML file to the CSS directory
      relative_path = Pathname.new(html_file).relative_path_from(Pathname.new(base_output_dir))
      depth = relative_path.to_s.count('/')
      css_path = "#{'../' * depth}css/custom.css"

      # Add CSS link before closing </head> tag
      css_link = "<link rel=\"stylesheet\" href=\"#{css_path}\" type=\"text/css\" />"
      updated_content = content.gsub('</head>', "#{css_link}\n</head>")

      # Fix breadcrumb navigation: replace _index.html with index.html
      updated_content = updated_content.gsub('_index.html', 'index.html')

      File.write(html_file, updated_content)
    end

    def self.build_releasehx_module
      # Build ReleaseHx module (schemagraphy and sourcerer are now externalized)
      files = Dir.glob(['lib/releasehx.rb', 'lib/releasehx/**/*.rb'])
      readme_path = 'lib/releasehx/README.adoc'

      {
        name: 'ReleaseHx',
        files: files,
        readme: readme_path,
        title: 'ReleaseHx API'
      }
    end

    def self.add_jekyll_front_matter
      puts 'Adding front matter to YARD API docs...'

      # Add front matter to YARD API documentation files
      api_files = Dir.glob('build/docs/docs/api/**/*.html')
      return if api_files.empty?

      api_files.each do |file|
        next if ['class_list.html', 'file_list.html', 'method_list.html'].include?(File.basename(file))

        content = File.read(file)
        next if content.start_with?('---')

        if File.basename(file) == 'index.html'
          # Main index gets explicit title and nav_order
          front_matter = <<~HEREDOC
            ---
            layout: null
            title: "ReleaseHx API"
            nav_order: 4
            ---
          HEREDOC
        else
          # Other files are auto-excluded from nav
          doc = Nokogiri::HTML(content)
          page_title = doc.title
          page_title = if page_title.nil? || page_title.strip.empty?
                         'API Documentation'
                       else
                         page_title.gsub(/\s+/, ' ').strip
                       end
          front_matter = <<~HEREDOC
            ---
            layout: null
            title: "#{page_title}"
            nav_exclude: true
            ---
          HEREDOC
        end
        File.write(file, front_matter + content)
      end
    end

    def self.build_jekyll_site
      # Switch into build/docs to perform bulld
      Dir.chdir('build/docs') do
        puts 'Running Jekyll build...'
        raise 'Jekyll build failed' unless system('bundle exec jekyll build')
      end
    end
  end
end

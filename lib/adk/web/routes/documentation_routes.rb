# File: lib/adk/web/routes/documentation_routes.rb
# frozen_string_literal: true

require 'kramdown' # Required for markdown processing
require 'kramdown-parser-gfm' # Required for GitHub Flavored Markdown
require 'pathname' # For robust path operations

module ADK
  module Web
    module DocumentationRoutes
      module Helpers
        # Robustly checks if a given file path is safe and contained within the docs root
        # @param file_path [String] The path to check
        # @return [Pathname, nil] The valid Pathname object if safe, nil otherwise
        def resolve_safe_doc_path(file_path)
          public_docs_pathname = Pathname.new(File.join(settings.root, 'public', 'docs')).cleanpath
          target_file_pathname = Pathname.new(File.expand_path(file_path)).cleanpath

          # Ensure the target path starts with the docs root path
          return nil unless target_file_pathname.to_s.start_with?(public_docs_pathname.to_s)

          # Ensure the file actually exists and is a file
          return nil unless target_file_pathname.exist? && target_file_pathname.file?

          target_file_pathname
        end

        def render_markdown(file_path)
          target_file_pathname = resolve_safe_doc_path(file_path)

          unless target_file_pathname
            logger.warn "Markdown render: Path not valid or safe. Target: '#{file_path}'"
            return nil
          end

          markdown_content = File.read(target_file_pathname.to_s, encoding: 'UTF-8')

          # Configure Kramdown with enhanced rendering options - now using GFM
          html = Kramdown::Document.new(
            markdown_content,
            input: 'GFM',               # GitHub Flavored Markdown
            syntax_highlighter: nil,    # We'll apply our custom highlighting via CSS
            hard_wrap: false            # Don't convert newlines to <br>
          ).to_html

          # Post-process HTML to add language tags to code blocks
          process_code_blocks(html)
        rescue Errno::ENOENT
          logger.warn "Markdown file not found (render_markdown): #{file_path}"
          nil
        rescue StandardError => e
          logger.error "Error rendering markdown for #{file_path}: #{e.message}"
          logger.error e.backtrace.join("\n") # Add backtrace to help debugging
          nil
        end

        # Process code blocks to add language classes and data attributes
        def process_code_blocks(html)
          # Find fenced code blocks with language specifications
          html.gsub(%r{<pre><code\s+class="language-(\w+)">(.*?)</code></pre>}m) do |match|
            language = ::Regexp.last_match(1)
            code_content = ::Regexp.last_match(2)
            # Replace with our enhanced version that adds data-lang attribute
            %(<pre data-lang="#{language}"><code class="language-#{language}">#{code_content}</code></pre>)
          end
        end

        def generate_summary(markdown_content, max_lines = 5)
          return '' if markdown_content.nil? || markdown_content.empty?

          lines = markdown_content.lines
          summary_lines = []
          non_empty_lines_count = 0
          lines.each do |line|
            stripped_line = line.strip
            if !stripped_line.empty? && !stripped_line.start_with?('#') # Ignore headers for summary start
              summary_lines << stripped_line
              non_empty_lines_count += 1
              break if non_empty_lines_count >= max_lines
            elsif !summary_lines.empty? && stripped_line.empty? # Break on first blank line after content started
              break
            elsif summary_lines.empty? && stripped_line.start_with?('#') # Skip leading headers
              next
            end
          end
          summary_lines.join(' ').gsub(/\*\*|\*|_|`/, '') # Basic stripping of markdown
        end
      end

      def self.registered(app)
        app.helpers Helpers # Register the helpers for use in routes

        # Route for Documentation Index (GET /docs)
        app.get '/docs' do
          logger.debug('--- GET /docs --- (DocumentationRoutes)')
          docs_root_path = Pathname.new(File.join(settings.root, 'public', 'docs'))
          logger.debug("Docs root resolved to: #{docs_root_path}")

          categorized_documents = {}

          begin
            # Process files directly in docs_root_path first (General category)
            general_docs = []
            Dir.glob(File.join(docs_root_path, '*.md')).sort.each do |md_file_path|
              pathname = Pathname.new(md_file_path)
              next if pathname.directory? # Skip directories if any found by glob

              filename_md = pathname.basename.to_s
              filename_no_ext = pathname.basename('.md').to_s
              title = filename_no_ext.gsub(/[-_]/, ' ').split.map(&:capitalize).join(' ')
              file_content = File.read(md_file_path, encoding: 'UTF-8')
              first_h1_match = file_content.match(/^#\s+(.+)$/)
              title = first_h1_match[1].strip if first_h1_match
              summary = generate_summary(file_content)

              general_docs << {
                title: title,
                path: filename_no_ext, # Path relative to docs_root for linking
                summary: summary
              }
            end
            categorized_documents['General'] = general_docs if general_docs.any?

            # Process subdirectories for categories
            Dir.glob(File.join(docs_root_path, '*/')).sort.each do |dir_path|
              category_pathname = Pathname.new(dir_path)
              category_name = category_pathname.basename.to_s.gsub(/[-_]/, ' ').split.map(&:capitalize).join(' ')
              category_docs = []

              Dir.glob(File.join(category_pathname, '*.md')).sort.each do |md_file_path|
                pathname = Pathname.new(md_file_path)
                filename_md = pathname.basename.to_s
                filename_no_ext = pathname.basename('.md').to_s
                full_relative_path = "#{category_pathname.basename}/#{filename_no_ext}"

                title = filename_no_ext.gsub(/[-_]/, ' ').split.map(&:capitalize).join(' ')
                file_content = File.read(md_file_path, encoding: 'UTF-8')
                first_h1_match = file_content.match(/^#\s+(.+)$/)
                title = first_h1_match[1].strip if first_h1_match
                summary = generate_summary(file_content)

                category_docs << {
                  title: title,
                  path: full_relative_path, # Path includes category dir
                  summary: summary
                }
              end
              categorized_documents[category_name] = category_docs if category_docs.any?
            end

            logger.warn("No markdown files or categories found in #{docs_root_path}") if categorized_documents.empty?
          rescue StandardError => e
            logger.error("Error scanning documentation directory: #{e.message}")
            logger.error(e.backtrace.first(5).join("\n"))
          end

          instance_variable_set(:@categorized_documents, categorized_documents)
          logger.debug("Setting @categorized_documents with #{categorized_documents.keys.count} categories.")
          logger.debug("Content of @categorized_documents: #{@categorized_documents.inspect}")

          slim :docs_index
        end

        # Route for Displaying a Single Document (GET /docs/*)
        # The splat parameter will capture the category/filename path
        app.get '/docs/*' do |path_splat|
          logger.debug("GET /docs/#{path_splat} - Entered (from DocumentationRoutes)")

          # Basic input sanitization (defense in depth), but real security is in resolve_safe_doc_path
          sane_path = path_splat.gsub(%r{^/+|/+$}, '')

          halt 404, slim(:error_404, locals: { title: 'Document Not Found', message: 'Invalid document path.' }) if sane_path.empty?

          # Ensure it's .md, even if not explicitly in splat
          file_path_to_check = sane_path.end_with?('.md') ? sane_path : "#{sane_path}.md"
          full_file_path = File.join(settings.root, 'public', 'docs', file_path_to_check)

          # --- SECURITY CHECK ---
          # Use the centralized helper to strictly validate the path containment
          safe_pathname = resolve_safe_doc_path(full_file_path)

          unless safe_pathname
            logger.warn("Access attempt to unsafe or missing path: #{full_file_path}")
            halt 404,
                 slim(:error_404,
                      locals: { title: 'Document Not Found',
                                message: "Document '#{sane_path}' not found." })
          end
          # --- END SECURITY CHECK ---

          logger.debug("Attempting to access document at: #{safe_pathname}")

          begin
            markdown_html = render_markdown(safe_pathname.to_s)

            if markdown_html.nil?
              halt 404,
                   slim(:error_404,
                        locals: { title: 'Document Not Found',
                                  message: "Document '#{sane_path}' not found or could not be rendered." })
            end

            instance_variable_set(:@doc_html_content, markdown_html)

            # Try to extract title from H1 in markdown content
            # Safe to read because we verified it with resolve_safe_doc_path
            doc_title_for_view = sane_path.split('/').last.gsub(/[-_]/, ' ').split.map(&:capitalize).join(' ') # Default

            markdown_content_for_title = File.read(safe_pathname.to_s, encoding: 'UTF-8')
            first_h1_match = markdown_content_for_title.match(/^#\s+(.+)$/)
            doc_title_for_view = first_h1_match[1].strip if first_h1_match

            instance_variable_set(:@doc_title, doc_title_for_view)

            slim :docs_show
          rescue StandardError => e
            logger.error("Error processing document #{sane_path}: #{e.message}")
            logger.error(e.backtrace.join("\n"))
            halt 500, 'Error displaying document.'
          end
        end
      end
    end
  end
end

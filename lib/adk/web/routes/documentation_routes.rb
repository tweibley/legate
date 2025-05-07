# File: lib/adk/web/routes/documentation_routes.rb
# frozen_string_literal: true

require 'kramdown' # Required for markdown processing
require 'kramdown-parser-gfm' # Required for GitHub Flavored Markdown
require 'pathname'   # For robust path operations

module ADK
  module Web
    module DocumentationRoutes
      
      module Helpers
        def render_markdown(file_path)
          begin
            public_docs_pathname = Pathname.new(File.expand_path(File.join(settings.root, 'public', 'docs')))
            target_file_pathname = Pathname.new(File.expand_path(file_path))

            # Check if the target file is within the public_docs_pathname directory
            # and is an actual file that exists.
            # The `ascend` method iterates upwards from the file to its parent directories.
            # We check if any of these parent paths match our intended docs root.
            is_within_docs_dir = false
            target_file_pathname.ascend do |p|
              if p == public_docs_pathname
                is_within_docs_dir = true
                break
              end
              break if p.root? # Stop if we reach the filesystem root
            end

            unless is_within_docs_dir && target_file_pathname.file? && target_file_pathname.exist?
              logger.warn "Markdown render: Path not valid or file does not exist. Target: '#{target_file_pathname}', Expected base: '#{public_docs_pathname}'"
              return nil
            end
            
            markdown_content = File.read(target_file_pathname.to_s)
            
            # Configure Kramdown with enhanced rendering options - now using GFM
            html = Kramdown::Document.new(
              markdown_content,
              input: 'GFM',               # GitHub Flavored Markdown
              syntax_highlighter: nil,    # We'll apply our custom highlighting via CSS
              hard_wrap: false            # Don't convert newlines to <br>
            ).to_html
            
            # Post-process HTML to add language tags to code blocks
            html = process_code_blocks(html)
            
            return html
          rescue Errno::ENOENT # Should be caught by File.exist? check now, but good fallback
            logger.warn "Markdown file not found (render_markdown): #{target_file_pathname}"
            nil
          rescue => e
            logger.error "Error rendering markdown for #{target_file_pathname}: #{e.message}"
            logger.error e.backtrace.join("\n") # Add backtrace to help debugging
            nil
          end
        end
        
        # Process code blocks to add language classes and data attributes
        def process_code_blocks(html)
          # Find fenced code blocks with language specifications
          html.gsub(/<pre><code\s+class="language-(\w+)">(.*?)<\/code><\/pre>/m) do |match|
            language = $1
            code_content = $2
            # Replace with our enhanced version that adds data-lang attribute
            %(<pre data-lang="#{language}"><code class="language-#{language}">#{code_content}</code></pre>)
          end
        end

        def generate_summary(markdown_content, max_lines = 5)
          return "" if markdown_content.nil? || markdown_content.empty?
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
      end # module Helpers

      def self.registered(app)
        app.helpers Helpers # Register the helpers for use in routes

        # Route for Documentation Index (GET /docs)
        app.get '/docs' do
          logger.debug("--- GET /docs --- (DocumentationRoutes)")
          docs_root = File.join(settings.root, 'public', 'docs')
          logger.debug("Docs root resolved to: #{docs_root}")
          
          documents = []
          begin
            markdown_files = Dir.glob(File.join(docs_root, '*.md')).sort
            logger.debug("Found markdown files: #{markdown_files.inspect}")

            if markdown_files.empty?
              logger.warn("No markdown files found in #{docs_root}")
            end

            markdown_files.each do |md_file_path|
              logger.debug("Processing file: #{md_file_path}")
              filename_md = File.basename(md_file_path)
              filename_no_ext = File.basename(filename_md, '.md')
              title = filename_no_ext.gsub(/[-_]/, ' ').split.map(&:capitalize).join(' ')
              
              file_content = ""
              begin
                file_content = File.read(md_file_path)
                logger.debug("Successfully read file: #{md_file_path}")
              rescue => read_err
                logger.error("Error reading file #{md_file_path}: #{read_err.message}")
                next # Skip this file
              end

              first_h1_match = file_content.match(/^#\s+(.+)$/)
              title = first_h1_match[1].strip if first_h1_match
              summary = generate_summary(file_content)
              
              documents << {
                title: title,
                filename: filename_no_ext,
                summary: summary
              }
              logger.debug("Added document: #{title}")
            end
          rescue => e
            logger.error("Error during Dir.glob or file processing: #{e.message}")
            logger.error(e.backtrace.first(5).join("\n"))
          end
          
          self.instance_variable_set(:@document_list_for_view, documents)
          logger.debug("Setting @document_list_for_view with #{documents.count} items.")
          logger.debug("Content of @document_list_for_view: #{@document_list_for_view.inspect}")
          
          slim :docs_index
        end

        # Route for Displaying a Single Document (GET /docs/:filename)
        app.get '/docs/:filename' do |filename|
          logger.debug("GET /docs/#{filename} - Entered (from DocumentationRoutes)")
          
          # Sanitize filename: allow alphanumeric, underscore, hyphen
          sane_filename = filename.gsub(/[^0-9a-zA-Z_-]/, '')
          if sane_filename.empty?
            logger.warn("Attempt to access doc with invalid filename: '#{filename}'")
            halt 404, slim(:error_404, locals: { title: "Document Not Found", message: "Invalid document name."})
          end

          # Correctly point to public/docs from the project root for individual files
          file_path = File.join(settings.root, 'public', 'docs', "#{sane_filename}.md")
          logger.debug("Attempting to access document at: #{file_path}")
          
          unless File.exist?(file_path)
            logger.warn("Documentation file not found: #{file_path}")
            halt 404, slim(:error_404, locals: { title: "Document Not Found", message: "Document '#{sane_filename}.md' not found."})
          end

          begin
            markdown_content = File.read(file_path)
            # Instance variables for the view are set on `self`
            self.instance_variable_set(:@doc_html_content, render_markdown(file_path))
            
            first_h1_match = markdown_content.match(/^#\s+(.+)$/)
            doc_title_for_view = if first_h1_match
                                     first_h1_match[1].strip
                                   else
                                     sane_filename.gsub(/[-_]/, ' ').split.map(&:capitalize).join(' ')
                                   end
            self.instance_variable_set(:@doc_title, doc_title_for_view)

            if self.instance_variable_get(:@doc_html_content).nil?
                logger.error("Markdown rendering failed for: #{file_path}")
                halt 500, "Error rendering document."
            end
            
            slim :docs_show
          rescue => e
            logger.error("Error processing document #{sane_filename}.md: #{e.message}")
            halt 500, "Error displaying document."
          end
        end
      end
    end
  end
end 
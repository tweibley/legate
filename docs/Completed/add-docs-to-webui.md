# Plan: Add Markdown Documentation to Web UI

This plan outlines the steps to integrate a documentation section into the ADK Web UI, allowing Markdown files stored in `public/docs` to be rendered and displayed, following a modular Sinatra application structure.

## 1. Dependency Setup

*   **Add Kramdown Gem**:
    *   Open `Gemfile`.
    *   Add the line: `gem 'kramdown'`
    *   Run `bundle install` in the terminal to install the gem.

## 2. Create Documentation Directory

*   Create a new directory: `public/docs`. This is where the Markdown documentation files will reside.
    *   Initially, we can add a placeholder file like `public/docs/introduction.md` with some basic markdown content for testing.

## 3. Create Documentation Routes Module

*   **Create File**:
    *   Create a new file: `lib/adk/web/routes/documentation_routes.rb`.
*   **Define Module Structure**:
    ```ruby
    # File: lib/adk/web/routes/documentation_routes.rb
    # frozen_string_literal: true

    require 'kramdown' # Required for markdown processing
    require 'pathname'   # For robust path operations

    module ADK
      module Web
        module DocumentationRoutes
          def self.registered(app)
            # Helper methods will be defined here or accessed via `app` if defined globally

            # Route for Documentation Index (GET /docs)
            app.get '/docs' do
              # ... logic from old plan ...
            end

            # Route for Displaying a Single Document (GET /docs/:filename)
            app.get '/docs/:filename' do |filename|
              # ... logic from old plan ...
            end
          end

          # Optional: Define helpers within this module if they are specific to docs
          # module Helpers
          #   def render_markdown(file_path)
          #     # ... implementation ...
          #   end
          #   def generate_summary(markdown_content, max_lines = 5)
          #     # ... implementation ...
          #   end
          # end
          # 
          # # If helpers are defined in the module, make them available
          # def self.registered(app)
          #   app.helpers Helpers # If helpers are defined in DocumentationRoutes::Helpers
          #   # ... routes ...
          # end
        end
      end
    end
    ```

*   **Implement Helper Methods (within `DocumentationRoutes` or as main app helpers)**:
    *   **`render_markdown(file_path)`**:
        *   Takes a full, validated file path to a Markdown document.
        *   Reads the file content.
        *   Uses `Kramdown::Document.new(markdown_content).to_html` to convert it to HTML.
        *   Returns the HTML string.
        *   Handles potential errors (e.g., file not found by returning `nil` or raising an error to be caught by the route).
    *   **`generate_summary(markdown_content, max_lines = 5)`**:
        *   Takes markdown content as a string.
        *   Extracts the first few lines (e.g., up to `max_lines` or until a blank line after some content).
        *   Potentially strips markdown formatting for a plain text summary.
        *   Returns a short summary string.
    *   *Note: If these helpers are defined within the `DocumentationRoutes` module (e.g., in a nested `Helpers` submodule), they would be made available to routes via `app.helpers DocumentationRoutes::Helpers` inside `self.registered(app)`. If they are general enough to be used elsewhere, they could be added to the main `ADK::Web::App` helpers block.* 

*   **Implement Route for Documentation Index (`GET /docs`)** (within `DocumentationRoutes`):
    *   This route will:
        *   Define `docs_root = File.join(settings.public_folder, 'docs')`.
        *   List all `.md` files in the `docs_root` directory (e.g., `Dir.glob(File.join(docs_root, '*.md'))`).
        *   For each file:
            *   Generate a title (e.g., from the filename, removing `.md` and title-casing it, or by reading the first H1 from the Markdown file).
            *   Generate a short summary using the `generate_summary` helper (after reading file content).
            *   Store as a list of document objects (e.g., `[{title: "Introduction", filename: "introduction", summary: "..."}, ...]`) - note filename without `.md` for the link.
        *   Pass this list to `docs_index.slim`.
        *   Render `slim :docs_index, locals: { documents: @document_list_for_view }` (or set instance variable `@document_list_for_view`).
*   **Implement Route for Displaying a Single Document (`GET /docs/:filename`)** (within `DocumentationRoutes`):
    *   This route will:
        *   Take `filename` from the path.
        *   **Sanitize `filename`**: Ensure it only contains alphanumeric characters, underscores, and hyphens to prevent directory traversal (e.g., `filename.gsub!(/[^0-9a-zA-Z_-]/, '')`).
        *   Construct the full path: `file_path = File.join(settings.public_folder, 'docs', "#{filename}.md")`.
        *   Check if the file exists (e.g., `File.exist?(file_path)`). If not, `halt 404, slim(:error_404, locals: { title: "Document Not Found"})`.
        *   Read file content. If error, handle gracefully (e.g., log and show error).
        *   Use the `render_markdown` helper to convert its content to HTML.
        *   Determine a title (e.g., from filename or first H1).
        *   Pass the HTML content and document title to `docs_show.slim`.
        *   Render `slim :docs_show, locals: { title: @doc_title, content_html: @doc_html_content }` (or set instance variables).

## 3.1. Modify Main Application (`lib/adk/web/app.rb`)

*   **Require the new module**:
    *   Add `require_relative 'routes/documentation_routes'` near other route module requires.
*   **Register the module**:
    *   Inside the `ADK::Web::App` class, add `register ADK::Web::DocumentationRoutes`.

## 4. Create Views (`lib/adk/web/views/`)

*   **`docs_index.slim`**:
    *   This view will:
        *   Display a title like "Documentation".
        *   Iterate through the list of document objects passed from the `/docs` route.
        *   For each document, display its title as a link to `/docs/:filename` (using the filename *without* `.md`).
        *   Display the short summary for each document.
        *   Use Bulma styling.
*   **`docs_show.slim`**:
    *   This view will:
        *   Display the title of the document.
        *   Render the HTML content (passed from the `/docs/:filename` route) using `==` in Slim to output raw HTML.
        *   Ensure basic styling for the rendered HTML content.
*   **`error_404.slim` (Enhancement)**:
    *   Ensure it can display a generic "Resource Not Found" or a specific "Document not found" message.

## 5. Update Main Layout

*   **Add Navigation Link**:
    *   In `lib/adk/web/views/layout.slim`, add a new navigation link (e.g., "Documentation") that points to `/docs`.

## 6. Styling (CSS)

*   Review rendered Markdown in `docs_show.slim`.
*   Add custom CSS if needed for Kramdown-generated elements.

## 7. Testing

*   Create sample Markdown files.
*   Test `/docs` index and individual document pages.
*   Test non-existent document URLs.
*   Check styling and responsiveness. 
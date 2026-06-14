# File: examples/12_http_client_tool.rb
# frozen_string_literal: true

require 'bundler/setup'
require 'legate' # Load Legate framework

# Load .env and map GEMINI_API_KEY -> GOOGLE_API_KEY (as the `legate` CLI does).
# The library never reads .env on its own; an application must opt in.
Legate.load_environment
require 'legate/tools/base/http_client' # Load the HttpClient module

# --- Define the Custom Tool ---
class JsonPlaceholderTool < Legate::Tool
  include Legate::Tools::Base::HttpClient # Include the mixin

  # --- Tool Metadata ---
  tool_name # Infer name from class: json_placeholder_tool
  tool_description 'Fetches or creates posts on JSONPlaceholder API.'

  parameter :action, type: :string, required: true, description: 'Action to perform: "get" or "create".'
  parameter :post_id, type: :integer, required: false, description: 'The ID of the post to fetch (required for "get").'
  parameter :post_data, type: :hash, required: false,
                        description: 'Data for the new post (required for "create"). Example: { title: "foo", body: "bar", userId: 1 }'
  # --- End Metadata ---

  API_BASE_URL = 'https://jsonplaceholder.typicode.com/'

  def initialize(**options)
    super(**options)
    # Setup the client for JSONPlaceholder
    # Use default options (timeouts, persistent connection, etc.)
    # Specify default Accept header
    setup_http_client(
      base_url: API_BASE_URL,
      headers: { 'Accept' => 'application/json' }
      # options: { read_timeout: 5 } # Example: Override default timeout
    )
    Legate.logger.info 'JsonPlaceholderTool initialized.'
  end

  private

  # Main logic for the tool
  def perform_execution(params, context)
    action = params.fetch(:action).downcase

    case action
    when 'get'
      fetch_post(params, context)
    when 'create'
      create_post(params, context)
    else
      raise Legate::ToolArgumentError, "Invalid action specified: '#{action}'. Use 'get' or 'create'."
    end

  # Rescue ToolErrors raised by HttpClient or argument validation
  rescue Legate::ToolError => e
    Legate.logger.error("JsonPlaceholderTool Error: #{e.class} - #{e.message}")
    # You might want more specific handling based on e.g., e.is_a?(Legate::ToolHttpError)
    { status: :error, error_message: "API operation failed: #{e.message}" }
  end

  # --- Helper Methods ---

  def fetch_post(params, _context)
    post_id = params[:post_id]
    raise Legate::ToolArgumentError, "Missing required parameter: post_id for action 'get'" unless post_id

    Legate.logger.info "Fetching post with ID: #{post_id}"
    # Use the http_get helper from HttpClient
    response = http_get("posts/#{post_id}") # Path relative to base_url

    # Parse the response body
    begin
      data = JSON.parse(response.body)
      { status: :success, result: data }
    rescue JSON::ParserError => e
      raise Legate::ToolError, "Failed to parse JSON response: #{e.message}"
    end
  end

  def create_post(params, _context)
    post_data = params[:post_data]
    unless post_data.is_a?(Hash) && !post_data.empty?
      raise Legate::ToolArgumentError,
            "Missing required parameter: post_data for action 'create'"
    end

    Legate.logger.info "Creating post with data: #{post_data.inspect}"
    # Use the http_post helper. Payload is a Hash, HttpClient handles JSON encoding
    # and sets Content-Type: application/json automatically.
    response = http_post('posts', body: post_data)

    # Check response status (optional, HttpClient raises ToolHttpError for 4xx/5xx)
    # Here we just return the parsed response body which includes the new ID
    begin
      created_post = JSON.parse(response.body)
      { status: :success, result: created_post }
    rescue JSON::ParserError => e
      raise Legate::ToolError, "Failed to parse JSON response after creating post: #{e.message}"
    end
  end
end

# --- Example Usage ---

# Ensure Legate logger is setup (usually done in main application)
Legate.logger.level = Logger::INFO

# Create an instance of the tool
placeholder_tool = JsonPlaceholderTool.new

# Create a dummy context (provide required keywords)
dummy_context = Legate::ToolContext.new(
  session_id: 'dummy-session-123',
  user_id: 'example-user',
  app_name: 'http_client_example'
)

# Example 1: Fetch post with ID 1
puts "\n--- Fetching Post 1 ---"
fetch_params = { action: 'get', post_id: 1 }
fetch_result = placeholder_tool.execute(fetch_params, context: dummy_context)
puts "Result: #{fetch_result.inspect}"

puts "\n--- Fetching Non-existent Post 999 ---"
fetch_params_bad = { action: 'get', post_id: 999 }
fetch_result_bad = placeholder_tool.execute(fetch_params_bad, context: dummy_context)
puts "Result: #{fetch_result_bad.inspect}" # Expects :error status due to 404

# Example 2: Create a new post
puts "\n--- Creating New Post ---"
create_params = {
  action: 'create',
  post_data: {
    title: 'Legate Test Post',
    body: 'This post was created by the Legate HttpClient example.',
    userId: 5
  }
}
create_result = placeholder_tool.execute(create_params, context: dummy_context)
puts "Result: #{create_result.inspect}" # Expects :success with new post data (including ID)

# Example 3: Invalid action
puts "\n--- Invalid Action (Expected Error) ---"
puts '(This demonstrates the tool raising ToolArgumentError for unsupported actions)'
invalid_params = { action: 'delete', post_id: 1 } # Action not supported by our tool
invalid_result = placeholder_tool.execute(invalid_params, context: dummy_context)
puts "Result: #{invalid_result.inspect}" # Expects :error status

# Example 4: Missing required param
puts "\n--- Missing Parameter (Expected Error) ---"
puts '(This demonstrates the tool raising ToolArgumentError for missing required params)'
missing_params = { action: 'get' } # Missing post_id
missing_result = placeholder_tool.execute(missing_params, context: dummy_context)
puts "Result: #{missing_result.inspect}" # Expects :error status

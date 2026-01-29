require_relative '../lib/adk'

# This script verifies the examples that will be added to ADK::Tool documentation.

puts "--> Verifying Tool Documentation Examples..."

# Example 1: Successful execution
class SuccessTool < ADK::Tool
  tool_description "A tool that always succeeds"
  parameter :input, type: :string, description: "Some input"

  def perform_execution(params, context)
    # Example logic
    result_data = "Processed: #{params[:input]}"

    { status: :success, result: result_data }
  end
end

# Example 2: Execution with error
class ErrorTool < ADK::Tool
  tool_description "A tool that always fails"

  def perform_execution(params, context)
    # Example logic
    { status: :error, error_message: "Something went wrong" }
  end
end

# Example 3: Asynchronous execution (pending)
class AsyncTool < ADK::Tool
  tool_description "A tool that is async"

  def perform_execution(params, context)
    # Example logic
    { status: :pending, job_id: "job_12345" }
  end
end

# Helper to run verify
def verify_tool(tool_class, params = {}, expected_status)
  tool = tool_class.new
  # Mock context as nil since our examples don't strictly use it,
  # but in real usage it would be an ADK::ToolContext
  context = nil

  result = tool.execute(params, context)

  if result[:status] == expected_status
    puts "✅ #{tool_class} returned #{expected_status}"
    puts "   Result: #{result.inspect}"
  else
    puts "❌ #{tool_class} failed! Expected #{expected_status}, got #{result[:status]}"
    puts "   Full Result: #{result.inspect}"
    exit 1
  end
end

# Run verifications
verify_tool(SuccessTool, { input: "test" }, :success)
verify_tool(ErrorTool, {}, :error)
verify_tool(AsyncTool, {}, :pending)

puts "All examples verified successfully!"

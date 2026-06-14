#!/usr/bin/env ruby
# frozen_string_literal: true

# If running from project root: bundle exec ruby examples/06_callbacks.rb
require_relative '../lib/legate'

# Load .env and map GEMINI_API_KEY -> GOOGLE_API_KEY (as the `legate` CLI does).
# The library never reads .env on its own; an application must opt in.
Legate.load_environment

puts '--- Legate Callbacks Basic Example ---'

# Helper method to safely inspect objects
def inspect_object(obj)
  return 'nil' if obj.nil?

  if obj.is_a?(Hash) || obj.is_a?(Array)
    obj.inspect
  else
    # For other objects, get their instance variables and methods
    vars = obj.instance_variables.map { |v| "#{v}=#{obj.instance_variable_get(v).inspect}" }
    methods = obj.public_methods(false).sort.map(&:to_s)
    "Object of class #{obj.class}\nInstance vars: #{vars.join(', ')}\nMethods: #{methods.join(', ')}"
  end
end

# 1. --- Define our callback functions ---

# Agent callbacks
before_agent_callback = lambda do |context|
  puts "\n[AGENT CALLBACK] Before agent processes request"
  puts "  Context structure: #{inspect_object(context)}"
  puts "  Session ID: #{context.session_id}" if context.respond_to?(:session_id)
end

# The documentation mentioned only 1 parameter, but the error suggests 2 are passed
after_agent_callback = lambda do |context, *args|
  puts "\n[AGENT CALLBACK] After agent completed request"
  puts "  Context structure: #{inspect_object(context)}"
  puts "  Additional args: #{args.inspect}" if args.any?
end

# Model callbacks - expecting 2 arguments
before_model_callback = lambda do |context, prompt|
  puts "\n[MODEL CALLBACK] Before sending prompt to LLM"
  puts "  Context structure: #{inspect_object(context)}"

  if prompt.is_a?(String)
    preview = prompt.length > 100 ? "#{prompt[0, 100]}..." : prompt
    puts "  Prompt: #{preview}"
  else
    puts "  Prompt: #{prompt.inspect}"
  end

  # Return the prompt unchanged
  prompt
end

after_model_callback = lambda do |context, response|
  puts "\n[MODEL CALLBACK] After receiving response from LLM"
  puts "  Context structure: #{inspect_object(context)}"

  if response.is_a?(String)
    preview = response.length > 100 ? "#{response[0, 100]}..." : response
    puts "  Response: #{preview}"
  else
    puts "  Response: #{response.inspect}"
  end

  # Return the response unchanged
  response
end

# Tool callbacks - expecting 3 arguments
before_tool_callback = lambda do |context, tool, params|
  puts "\n[TOOL CALLBACK] Before executing tool"
  puts "  Context structure: #{inspect_object(context)}"
  puts "  Tool: #{tool.name}" if tool.respond_to?(:name)
  puts "  Parameters: #{params.inspect}"

  # Return the original parameters, not the context or tool
  # The expected parameters format is a Hash like {message: "Hello, world"}
  if params.is_a?(Hash)
    params
  elsif params.is_a?(Legate::ToolContext)
    # If we're passed a ToolContext object, try to extract parameters from session
    puts '  WARNING: Received ToolContext instead of params hash'

    # Get parameters from the session events if possible
    if params.respond_to?(:session_id) && params.session_id && defined?($session_service)
      begin
        session = $session_service.get_session(session_id: params.session_id)
        if session
          events = session.events
          # Find the most recent tool_request event for this tool
          tool_name = tool.respond_to?(:name) ? tool.name.to_s : nil
          if tool_name
            # The tool field might be stored in different ways
            tool_request = events.reverse.find do |e|
              e.role == :tool_request &&
                ((e.respond_to?(:tool) && e.tool == tool_name) ||
                 (e.respond_to?(:[]) && e[:tool] == tool_name))
            end

            if tool_request && tool_request.respond_to?(:content) && tool_request.content.is_a?(Hash)
              # We found the parameters in the session events
              return tool_request.content
            end
          end
        end
      rescue StandardError => e
        puts "  WARNING: Error getting session events: #{e.message}"
      end
    end

    # Default fallback for echo tool
    { message: 'Hello, world! This is a callback example.' }
  else
    # If all else fails, return empty params
    puts "  WARNING: Unexpected params type: #{params.class}"
    {}
  end
end

after_tool_callback = lambda do |context, tool, result|
  puts "\n[TOOL CALLBACK] After executing tool"
  puts "  Context structure: #{inspect_object(context)}"
  puts "  Tool: #{tool.name}" if tool.respond_to?(:name)
  puts "  Result: #{result.inspect}"

  # Return the result unchanged
  result
end

# 2. --- Agent Definition with Callbacks ---
echo_agent_definition = Legate::AgentDefinition.new.define do |a|
  a.name :echo_with_callbacks
  a.description 'An echo agent that demonstrates callbacks'
  a.instruction 'You are an echo agent. Your task is to repeat the user\'s input exactly.'

  # Register the callbacks
  a.before_agent_callback(&before_agent_callback)
  a.after_agent_callback(&after_agent_callback)

  a.before_model_callback(&before_model_callback)
  a.after_model_callback(&after_model_callback)

  a.before_tool_callback(&before_tool_callback)
  a.after_tool_callback(&after_tool_callback)

  a.use_tool :echo
end

# 3. --- Agent Instantiation ---
agent = Legate::Agent.new(definition: echo_agent_definition)
puts "\nAgent '#{agent.name}' created with callbacks registered"

# 4. --- Start Agent and Setup Session ---
agent.start
session_service = Legate::SessionService::InMemory.new
# Make session_service accessible to callbacks
$session_service = session_service
session = session_service.create_session(app_name: agent.name, user_id: 'callback_example_user')
session_id = session.id
puts "\nCreated session: #{session_id}"

# 5. --- Execute Task and Observe Callbacks ---
task = 'Hello, world! This is a callback example.'
puts "\nExecuting task: '#{task}'"

begin
  result = agent.run_task(
    session_id: session_id,
    user_input: task,
    session_service: session_service
  )

  puts "\nFinal result: #{result.content.inspect}"
rescue StandardError => e
  puts "\nError executing task: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

# 6. --- Stop Agent ---
agent.stop
puts "\n--- Example Complete ---"

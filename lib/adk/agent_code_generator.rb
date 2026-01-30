# frozen_string_literal: true

require_relative 'generators/agent_source_generator'

module ADK
  # Deprecated: Use ADK::Generators::AgentSourceGenerator instead.
  # Maintained for backward compatibility.
  AgentCodeGenerator = ADK::Generators::AgentSourceGenerator
end

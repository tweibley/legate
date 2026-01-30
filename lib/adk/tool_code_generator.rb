# frozen_string_literal: true

require_relative 'generators/tool_source_generator'

module ADK
  # Deprecated: Use ADK::Generators::ToolSourceGenerator instead.
  # Maintained for backward compatibility.
  ToolCodeGenerator = ADK::Generators::ToolSourceGenerator
end

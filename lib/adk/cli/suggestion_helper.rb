# frozen_string_literal: true

require 'did_you_mean'

module ADK
  module CLI
    # Helper for providing suggestions for invalid inputs
    module SuggestionHelper
      def suggest_agent_name(invalid_name)
        return nil unless defined?(DidYouMean::SpellChecker)

        valid_names = ADK::AgentDefinitionStore.all_names
        return nil if valid_names.empty?

        checker = DidYouMean::SpellChecker.new(dictionary: valid_names)
        suggestion = checker.correct(invalid_name).first

        suggestion ? " Did you mean '#{suggestion}'?" : nil
      end
    end
  end
end

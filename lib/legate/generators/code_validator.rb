# frozen_string_literal: true

require 'ripper'

module Legate
  module Generators
    module CodeValidator
      BLOCKED_IDENTS = %w[system exec eval instance_eval class_eval module_eval popen].freeze
      BLOCKED_CONSTS = %w[Open3].freeze

      class UnsafeCodeError < StandardError; end

      module_function

      def validate!(code)
        validate_syntax!(code)
        validate_no_dangerous_calls!(code)
      end

      def validate_syntax!(code)
        sexp = Ripper.sexp(code)
        raise UnsafeCodeError, 'Generated code has Ruby syntax errors and cannot be saved.' unless sexp
      end

      def validate_no_dangerous_calls!(code)
        tokens = Ripper.lex(code)
        dangerous = []

        tokens.each do |(_, type, token, _)|
          case type
          when :on_backtick
            dangerous << 'backtick command execution'
          when :on_ident
            dangerous << "`#{token}`" if BLOCKED_IDENTS.include?(token)
          when :on_const
            dangerous << "`#{token}`" if BLOCKED_CONSTS.include?(token)
          end
        end

        return if dangerous.empty?

        raise UnsafeCodeError,
              "Generated code contains potentially dangerous calls: #{dangerous.uniq.join(', ')}. " \
              'Review the code manually before saving.'
      end
    end
  end
end

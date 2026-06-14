# File: lib/legate/cli/base_command.rb
# frozen_string_literal: true

require 'thor'

module Legate
  module CLI
    # Base class for every Legate CLI command group.
    #
    # Thor 1.5 ships a built-in `tree` command on the base Thor class. Left
    # alone it leaks into help output namespaced by the implementation class
    # (e.g. `legate tool_commands tree`), which looks like a bug. We hide it
    # here once so all command groups inherit clean help output.
    class BaseCommand < Thor
      # The method body is intentionally a bare `super`: redefining `tree` here
      # is what lets the preceding `hide: true` take effect, suppressing Thor's
      # inherited (visible) command without changing its behavior.
      desc 'tree', 'Print a tree of all available commands', hide: true
      def tree # rubocop:disable Lint/UselessMethodDefinition
        super
      end
    end
  end
end

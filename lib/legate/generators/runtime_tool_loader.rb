# frozen_string_literal: true

require 'fileutils'
require_relative 'code_validator'

module Legate
  module Generators
    # Loads an AI-generated custom tool into the RUNNING process.
    #
    # SECURITY: this executes LLM-generated Ruby in-process. Ruby has no true
    # in-process sandbox, and CodeValidator is a denylist (blocks system/exec/eval/
    # popen/Open3) — not a jail. This path is therefore gated three ways:
    #   1. Config: Legate.config.allow_runtime_tool_load (default ON outside prod).
    #   2. The web UI requires an explicit per-tool "this runs code" confirmation.
    #   3. The source is re-validated here, server-side, before loading.
    # All loads are serialized through LOAD_MUTEX and wrapped in a broad rescue so a
    # bad generated tool can never crash the server. The tool is written to tools/
    # so it is auditable in source control and re-loaded on next boot.
    module RuntimeToolLoader
      LOAD_MUTEX = Mutex.new

      module_function

      # @return [Boolean] whether runtime tool loading is permitted by config.
      def enabled?
        Legate.config.allow_runtime_tool_load
      end

      # Validate, persist to tools/<name>.rb, and load the tool into this process.
      # Never raises — always returns a result hash.
      # @param source [String] the generated Ruby tool source.
      # @param suggested_name [String] basis for the file name.
      # @return [Hash] { ok: true, tool_name:, path: } or { ok: false, error: }
      def load_source!(source, suggested_name:)
        return { ok: false, error: 'Runtime tool loading is disabled in this environment.' } unless enabled?

        CodeValidator.validate!(source)

        name = sanitize_name(suggested_name)
        return { ok: false, error: 'Could not derive a valid tool file name.' } if name.empty?

        path = File.join(tools_dir, "#{name}.rb")
        before = Legate::GlobalToolManager.registered_tool_names

        LOAD_MUTEX.synchronize do
          FileUtils.mkdir_p(tools_dir)
          File.write(path, source)
          # `load` (not `require`) so re-generating the same tool reloads it.
          load(path)
        end

        added = Legate::GlobalToolManager.registered_tool_names - before
        return { ok: false, error: 'The generated code did not register a tool (missing GlobalToolManager.register_tool call).' } if added.empty?

        { ok: true, tool_name: added.first.to_s, path: path }
      rescue CodeValidator::UnsafeCodeError => e
        { ok: false, error: e.message }
      rescue Exception => e # rubocop:disable Lint/RescueException
        # Broad on purpose: generated code can raise SyntaxError/NameError/LoadError
        # at file scope. A bad tool must never take down the server.
        Legate.logger.error("RuntimeToolLoader failed for '#{suggested_name}': #{e.class} - #{e.message}")
        { ok: false, error: "#{e.class}: #{e.message}" }
      end

      # Where generated tools are written. Matches the boot loader's `tools/` glob
      # (TOOL_DIRECTORIES) so the tool is re-loaded on the next server start.
      def tools_dir
        File.join(Dir.pwd, 'tools')
      end

      def sanitize_name(raw)
        raw.to_s.strip.sub(/\A:/, '').downcase.gsub(/[^a-z0-9_]+/, '_').gsub(/\A_+|_+\z/, '')
      end
    end
  end
end

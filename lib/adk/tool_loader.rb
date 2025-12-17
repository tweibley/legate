# frozen_string_literal: true

require 'logger'

module ADK
  # Responsible for discovering and loading tool definition files from the filesystem.
  # This decouples filesystem traversal and file loading from the Agent execution logic.
  module ToolLoader
    # Discovers and loads tool definition files from specified paths.
    # @param paths [Array<String>] An array of directory paths to search.
    # @return [void]
    def self.load_from_paths(paths)
      return if paths.nil? || paths.empty?

      ADK.logger.debug("Starting tool discovery in paths: #{paths.inspect}")

      paths.each do |path|
        absolute_dir_path = File.expand_path(path, Dir.pwd)

        unless Dir.exist?(absolute_dir_path)
          ADK.logger.warn("Tool discovery path does not exist or is not a directory: '#{path}' (resolved to '#{absolute_dir_path}'). Skipping.")
          next
        end

        Dir.glob(File.join(absolute_dir_path, '*.rb')).each do |absolute_file_path|
          ADK.logger.debug("Attempting to load tool file using 'require': #{absolute_file_path}")
          # Use require instead of load to prevent re-registration issues
          require absolute_file_path
          ADK.logger.debug("Successfully required (or already required): #{absolute_file_path}")
        rescue LoadError, SyntaxError => e
          ADK.logger.error("Failed to require/eval tool file '#{absolute_file_path}': #{e.class} - #{e.message}")
        rescue StandardError => e
          ADK.logger.error("Error encountered while requiring/processing tool file '#{absolute_file_path}': #{e.class} - #{e.message}")
        end
      end
      ADK.logger.debug('Finished tool discovery.')
    end
  end
end

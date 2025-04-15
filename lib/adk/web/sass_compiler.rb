# frozen_string_literal: true

require 'sass-embedded'
require 'fileutils'
require 'logger'

module ADK
  module Web
    # Sass compiler for the web interface
    class SassCompiler
      class << self
        def compile_all
          new.compile_all
        end
      end

      def initialize
        @logger = Logger.new($stdout)
        @logger.level = Logger::INFO
      end

      def compile_all
        @logger.info('Compiling Sass files...')

        # Ensure the output directory exists
        FileUtils.mkdir_p(output_dir)

        # Find all Sass files
        sass_files = Dir.glob(File.join(source_dir, '**', '*.scss'))

        sass_files.each do |sass_file|
          compile_file(sass_file)
        end

        @logger.info('Sass compilation complete!')
      end

      def compile_file(sass_file)
        relative_path = sass_file.sub("#{source_dir}/", '')
        output_file = File.join(output_dir, relative_path.sub('.scss', '.css'))

        # Ensure the output directory exists
        FileUtils.mkdir_p(File.dirname(output_file))

        @logger.info("Compiling #{relative_path} to #{output_file.sub("#{output_dir}/", '')}")

        begin
          # Compile the Sass file
          input = File.read(sass_file)
          result = Sass.compile_string(input, style: 'expanded', load_paths: [File.dirname(sass_file)])

          # Write the compiled CSS to the output file
          File.write(output_file, result.css)

          @logger.info("Successfully compiled #{relative_path}")
        rescue StandardError => e
          @logger.error("Error compiling #{relative_path}: #{e.message}")
          @logger.error(e.backtrace.join("\n"))
        end
      end

      private

      def source_dir
        @source_dir ||= File.expand_path('../public/styles', __FILE__)
      end

      def output_dir
        @output_dir ||= File.expand_path('../public/css', __FILE__)
      end
    end
  end
end

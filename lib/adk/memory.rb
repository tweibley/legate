# frozen_string_literal: true

require 'concurrent'
require 'json'

module ADK
  # Memory class represents the memory of an agent
  class Memory
    attr_reader :agent

    # Initialize a new memory
    # @param agent [Agent] The agent this memory belongs to
    # @param options [Hash] Additional options for the memory
    def initialize(agent:, **options)
      @agent = agent
      @short_term = Concurrent::Map.new
      @long_term = options[:storage] || {}
      @max_short_term_size = options[:max_short_term_size] || 100
    end

    # Remember something in short-term memory
    # @param key [Symbol] The key to remember
    # @param value [Object] The value to remember
    # @return [Object] The value
    def remember(key, value)
      if @short_term.size >= @max_short_term_size
        # Remove oldest entry if at capacity
        @short_term.shift
      end
      @short_term[key] = value
    end

    # Recall something from short-term memory
    # @param key [Symbol] The key to recall
    # @return [Object] The value
    def recall(key)
      @short_term[key]
    end

    # Store something in long-term memory
    # @param key [Symbol] The key to store
    # @param value [Object] The value to store
    # @return [Object] The value
    def store(key, value)
      @long_term[key] = value
    end

    # Retrieve something from long-term memory
    # @param key [Symbol] The key to retrieve
    # @return [Object] The value
    def retrieve(key)
      @long_term[key]
    end

    # Forget something from short-term memory
    # @param key [Symbol] The key to forget
    # @return [Object] The forgotten value
    def forget(key)
      @short_term.delete(key)
    end

    # Remove something from long-term memory
    # @param key [Symbol] The key to remove
    # @return [Object] The removed value
    def remove(key)
      @long_term.delete(key)
    end

    # Clear short-term memory
    # @return [self]
    def clear_short_term
      @short_term.clear
      self
    end

    # Clear long-term memory
    # @return [self]
    def clear_long_term
      @long_term.clear
      self
    end

    # Get all short-term memory
    # @return [Hash] The short-term memory
    def short_term_memory
      @short_term.to_h
    end

    # Get all long-term memory
    # @return [Hash] The long-term memory
    def long_term_memory
      @long_term.to_h
    end

    # Save memory to a file
    # @param file [String] The file to save to
    # @return [self]
    def save(file)
      data = {
        short_term: short_term_memory,
        long_term: long_term_memory
      }
      File.write(file, JSON.pretty_generate(data))
      self
    end

    # Load memory from a file
    # @param file [String] The file to load from
    # @return [self]
    def load(file)
      data = JSON.parse(File.read(file), symbolize_names: true)
      data[:short_term].each { |k, v| remember(k, v) }
      data[:long_term].each { |k, v| store(k, v) }
      self
    end
  end
end 
# ADK Ruby Demo Plan: News Aggregator Agent (External Project)

## Goal

To showcase how a user can easily build a functional AI agent using the `adk-ruby` gem. We will create a **separate, minimal demo project** that depends on `adk-ruby`. This project will build a simple agent that fetches news articles from an RSS feed based on a user-specified topic and **explicitly summarizes them using a second tool**. This approach mirrors how users would realistically integrate the library and demonstrates tool chaining.

## Key Features Demonstrated (from a User's Perspective)

*   **Gem Integration:** Adding `adk-ruby` and other required gems (`rss`, `gemini-ai`, `dotenv`).
*   **Agent Definition:** Creating an `ADK::Agent` instance within the user's project.
*   **Custom Tool Development:** Defining two tool classes (`RssFetcherTool`, `SummarizerTool`) inheriting from `ADK::Tool` *outside* the core library.
*   **Tool Registration & Instantiation:** Tools registered via `define_metadata` and instantiated via `GlobalToolManager`.
*   **Multi-step Planning & Execution:** The agent automatically plans and executes the fetch-then-summarize workflow using distinct tools.
*   **LLM Integration:** Leveraging an LLM (Gemini) both implicitly via the planner and *explicitly* within the `SummarizerTool`.
*   **Parameter Injection:** The planner passes the fetched articles from `RssFetcherTool` to `SummarizerTool`.
*   **Running the Agent:** Executing the agent via a simple script in the demo project.

## Demo Agent: `NewsAgent`

*   **Name:** `news_agent`
*   **Description:** "An agent that fetches articles from an RSS feed for a specific topic and provides a summary."
*   **Model:** Uses the default planner configured via environment variables (e.g., Gemini).

## Required Tools (in Demo Project)

1.  **`RssFetcherTool` (Custom Tool)**
    *   **Purpose:** Fetches and filters articles from a specified RSS feed URL.
    *   **Implementation:** Resides within the demo project (e.g., `demo_project/tools/rss_fetcher_tool.rb`).
    *   **Parameters:**
        *   `topic` (String): Keyword(s) to filter article titles/descriptions.
        *   `feed_url` (String): The URL of the RSS feed.
        *   `max_items` (Integer, optional, default: 5): Maximum number of *matching* articles to return.
    *   **Returns:** `{ status: :success, result: Array<Hash> }` where each Hash represents an article (e.g., `{ title: String, link: String, description: String }`).
    *   **Implementation Notes:** Requires the `rss` gem.

2.  **`SummarizerTool` (Custom Tool)**
    *   **Purpose:** Summarizes a list of provided articles using an LLM.
    *   **Implementation:** Resides within the demo project (e.g., `demo_project/tools/summarizer_tool.rb`).
    *   **Parameters:**
        *   `articles` (Array<Hash>): The list of articles (output from `RssFetcherTool`). Each hash should contain at least `:title` and `:description`.
    *   **Returns:** `{ status: :success, result: String }` containing the summary text.
    *   **Implementation Notes:** Requires the `gemini-ai` gem and a `GOOGLE_API_KEY` environment variable. Makes an external call to the Gemini API.

## Example Workflow (Revised)

1.  **User Input:** "Get the latest 3 articles about 'Ruby on Rails' from the Ruby Weekly RSS feed (https://rubyweekly.com/rss/) and summarize them."
2.  **Planner (e.g., Gemini):** Analyzes the input and determines the steps:
    *   **Step 1:** Call `RssFetcherTool` with `topic='Ruby on Rails'`, `feed_url='https://rubyweekly.com/rss/'`, `max_items=3`.
    *   **Step 2:** Call `SummarizerTool` with `articles=[Result from step 1]`.
3.  **Execution:**
    *   `RssFetcherTool` executes, fetches the feed, filters articles, returns the array of article data.
    *   `SummarizerTool` receives the article data, formats it, calls the Gemini API for summarization, and returns the summary text.
4.  **Output:** The agent returns an `ADK::Event` containing the final summary string.

## Implementation Steps (Revised for External Project)

1.  **Create Demo Project:** Set up a new directory (e.g., `adk-news-demo/`).
2.  **Demo Project `Gemfile`:** Create a `Gemfile` in the demo project root:
    ```ruby
    source 'https://rubygems.org'

    gem 'adk-ruby', path: '../adk-ruby' # Or use version constraint if published
    gem 'rss'
    gem 'gemini-ai' # For the SummarizerTool
    gem 'dotenv'
    ```
3.  **Install Dependencies:** Run `bundle install` inside the `adk-news-demo/` directory.
4.  **Tool Implementation (`RssFetcherTool`):** Create `adk-news-demo/tools/rss_fetcher_tool.rb`. Implement the class inheriting from `ADK::Tool`.
    ```ruby
    # tools/rss_fetcher_tool.rb
    require 'adk/tool'
    require 'rss'
    require 'open-uri'

    # A tool to fetch and filter items from an RSS feed based on a topic.
    class RssFetcherTool < ADK::Tool
      # Define the tool's metadata including its name, description, and parameters.
      # This also registers the tool with the GlobalToolManager.
      define_metadata(
        name: :rss_fetcher,
        description: 'Fetches and filters items from an RSS feed based on a topic.',
        parameters: {
          topic: { type: :string, description: 'Keyword(s) to filter article titles/descriptions.', required: true },
          feed_url: { type: :string, description: 'The URL of the RSS feed.', required: true },
          max_items: { type: :integer, description: 'Maximum number of matching articles to return.', default: 5 }
        }
      )

      # The main execution logic for the tool.
      # Note: The agent passes both params and context to this method.
      def execute(params, context = nil)
        topic = params[:topic].downcase
        feed_url = params[:feed_url]
        max_items = params[:max_items]

        ADK.logger.info("#{self.class.name}") { "Fetching feed: #{feed_url} for topic: '#{topic}', max_items: #{max_items}" }

        found_items = []
        begin
          # Open and parse the RSS feed.
          # Using open-uri for simplicity, consider more robust HTTP clients for production.
          URI.open(feed_url) do |rss|
            feed = RSS::Parser.parse(rss)
            ADK.logger.debug("#{self.class.name}") { "Feed '#{feed.channel.title}' fetched successfully. Items: #{feed.items.size}" }

            # Iterate through feed items, filter by topic, and collect results.
            feed.items.each do |item|
              title = item.title || ''
              description = item.description || ''

              # Simple case-insensitive search in title or description.
              if title.downcase.include?(topic) || description.downcase.include?(topic)
                ADK.logger.debug("#{self.class.name}") { "Found matching item: #{title}" }
                found_items << {
                  title: title,
                  link: item.link || 'N/A',
                  description: description, # Keep original description for summary
                  published_date: item.pubDate || 'N/A'
                }
              end

              # Stop if we've found enough items.
              break if found_items.size >= max_items
            end
          end
        rescue RSS::NotWellFormedError => e
          ADK.logger.error("#{self.class.name}") { "Error parsing RSS feed at #{feed_url}: #{e.message}" }
          # Return standard error format
          return { status: :error, error_message: "Failed to parse RSS feed: #{e.message}" }
        rescue StandardError => e # Catch other potential errors (network, etc.)
          ADK.logger.error("#{self.class.name}") { "Error fetching or processing feed #{feed_url}: #{e.message}" }
          # Return standard error format
          return { status: :error, error_message: "Failed to fetch or process feed: #{e.message}" }
        end

        ADK.logger.info("#{self.class.name}") { "Found #{found_items.size} items matching topic '#{topic}'" }

        # Return the array of found items wrapped in the standard success format
        { status: :success, result: found_items }
      end
    end
    ```
5. **Tool Implementation (`SummarizerTool`):** Create `adk-news-demo/tools/summarizer_tool.rb`.
    ```ruby
    # tools/summarizer_tool.rb
    require 'adk/tool'
    require 'gemini-ai'

    # A tool to summarize provided text using the Gemini API.
    class SummarizerTool < ADK::Tool
      define_metadata(
        name: :summarizer,
        description: 'Summarizes a list of provided articles using an LLM.',
        parameters: {
          articles: { type: :array, description: 'An array of article hashes, each with :title and :description.', required: true }
        }
      )

      # Executes the summarization.
      def execute(params, context = nil)
        articles = params[:articles]
        api_key = ENV['GOOGLE_API_KEY']

        unless api_key
          msg = "#{self.class.name}: GOOGLE_API_KEY environment variable not set."
          ADK.logger.error(msg)
          return { status: :error, error_message: msg }
        end

        unless articles.is_a?(Array) && !articles.empty?
          msg = "#{self.class.name}: Invalid or empty 'articles' parameter provided."
          ADK.logger.error(msg)
          return { status: :error, error_message: msg }
        end

        # Format articles for the prompt
        # Limit description length to avoid overly long prompts
        formatted_text = articles.map do |article|
          title = article[:title] || article['title'] || 'No Title'
          desc = article[:description] || article['description'] || 'No Description'
          "Title: #{title}\nDescription: #{desc[0, 500]}...\n---"
        end.join("\n\n")

        prompt = "Please provide a concise summary of the following articles:\n\n#{formatted_text}"

        ADK.logger.info("#{self.class.name}") { "Sending summarization request to Gemini for #{articles.size} articles." }
        ADK.logger.debug("#{self.class.name}") { "Summarization Prompt Snippet: #{prompt[0, 200]}..." }

        begin
          # Initialize the Gemini client using the correct model for the generative-language-api service
          client = Gemini.new(
            credentials: { service: 'generative-language-api', api_key: api_key },
            options: { model: 'gemini-1.5-flash', server_sent_events: false } # Use flash model
          )
          
          # Use stream_generate_content as it might be more broadly supported
          # Collect the response chunks and join the text parts
          response_chunks = client.stream_generate_content(
            { contents: { role: 'user', parts: { text: prompt } } }
          )

          # Process the response chunks to extract the full text
          # Check if response_chunks is an array and handle potential errors
          if response_chunks.is_a?(Array) && !response_chunks.empty?
            # Check the first chunk for immediate errors if the API returns them that way
            # (The gem might raise exceptions on HTTP errors already)
            first_candidate = response_chunks.first&.dig('candidates', 0)
            if first_candidate&.dig('finishReason') == 'SAFETY'
              safety_ratings = first_candidate['safetyRatings']
              msg = "#{self.class.name}: Gemini API request blocked due to safety settings. Ratings: #{safety_ratings.inspect}"
              ADK.logger.error(msg)
              return { status: :error, error_message: msg }
            end

            # Join text parts from all chunks and candidates
            summary = response_chunks.map do |chunk|
              chunk&.dig('candidates', 0, 'content', 'parts')&.map { |part| part['text'] }&.join
            end.compact.join
            
            if summary.nil? || summary.empty?
               # Handle cases where the response structure is unexpected or content is empty
               ADK.logger.error("#{self.class.name}: Gemini API response structure unexpected or content empty. Chunks: #{response_chunks.inspect}")
               return { status: :error, error_message: "Gemini API returned empty or unparsable summary." }
            end

            ADK.logger.info("#{self.class.name}") { "Received summary from Gemini." }
            { status: :success, result: summary.strip }
          else
            # Handle cases where response_chunks is not as expected
            ADK.logger.error("#{self.class.name}: Unexpected response format from stream_generate_content: #{response_chunks.inspect}")
            return { status: :error, error_message: "Gemini API returned unexpected response format." }
          end

        rescue Gemini::Errors::RequestError => e
          # Catch specific gem errors if possible (check gem source for error classes)
          ADK.logger.error("#{self.class.name}") { "Gemini API Request Error: #{e.class} - #{e.message} Payload: #{e.try(:payload).inspect}" }
          { status: :error, error_message: "Gemini API request error: #{e.message}" }
        rescue Faraday::Error => e # Catch Faraday connection errors
          ADK.logger.error("#{self.class.name}") { "Faraday Connection Error: #{e.class} - #{e.message}" }
          { status: :error, error_message: "Network error communicating with Gemini API: #{e.message}" }
        rescue StandardError => e
          ADK.logger.error("#{self.class.name}") { "Error calling Gemini API: #{e.class} - #{e.message}" }
          ADK.logger.error(e.backtrace.first(5).join("\n")) # Log part of backtrace
          { status: :error, error_message: "Failed to summarize articles: #{e.message}" }
        end
      end
    end
    ```
6. **Runner Script:** Create `adk-news-demo/run_news_agent.rb`:
    ```ruby
    require 'bundler/setup'
    require 'adk' # Load the ADK gem
    require 'dotenv'
    require_relative 'tools/rss_fetcher_tool'
    require_relative 'tools/summarizer_tool'

    # Load .env file from demo project
    Dotenv.load

    # Configure ADK (optional, if defaults aren't sufficient)
    # ADK.configure do |config|
    #   config.log_level = :INFO
    # end

    # --- Tool classes are registered implicitly when their files are required ---

    # --- 1. Define the Agent ---
    agent = ADK::Agent.new(
      name: 'news_agent',
      description: 'Fetches and summarizes news from RSS feeds.'
      # model_name: 'gemini-pro' # Optional: If different from default
    )

    # --- 2. Add Tool Instances to the Agent ---
    # Tools are registered globally via define_metadata, create instances here.
    rss_tool = ADK::GlobalToolManager.create_instance(:rss_fetcher)
    unless rss_tool
      raise "Error: Could not create instance of :rss_fetcher tool."
    end
    agent.add_tool(rss_tool)

    summarizer_tool = ADK::GlobalToolManager.create_instance(:summarizer)
    unless summarizer_tool
      raise "Error: Could not create instance of :summarizer tool."
    end
    agent.add_tool(summarizer_tool)

    # --- Start the agent runtime ---
    agent.start

    # --- 3. Setup Session ---
    session_service = ADK::SessionService::InMemory.new
    session = session_service.create_session(app_name: agent.name, user_id: 'demo_user')

    # --- 4. Define User Input ---
    user_input = "Get the latest 2 articles about 'Ruby' from the Ruby Weekly RSS feed (https://rubyweekly.com/rss/) and summarize them."

    # --- 5. Run the Task ---
    puts "Running task for Session: #{session.id}"
    puts "User Input: #{user_input}"

    result_event = agent.run_task(
      session_id: session.id,
      user_input: user_input,
      session_service: session_service
    )

    # --- 6. Display Result ---
    puts "\n--- Agent Result ---"
    require 'json'
    # Improve output clarity for success
    if result_event.content[:status] == :success
      puts "Status: Success"
      puts "Summary:\n#{result_event.content[:result]}"
      # Optionally show plan details for debugging/demo
      if result_event.content[:plan_details]
        puts "\n--- Plan Details ---"
        puts JSON.pretty_generate(result_event.content[:plan_details])
      end
    else
      puts "Status: Error"
      puts JSON.pretty_generate(result_event.to_h) # Show full event on error
    end
    puts "--------------------\n"
    ```
7. **Environment Setup:** Create `.env` file in `adk-news-demo/` with `GEMINI_API_KEY`.
8. **Testing:** Navigate to `adk-news-demo/` and run `bundle exec ruby run_news_agent.rb`. Verify the output includes a summary.
9. **Documentation (in `adk-ruby` repo):** Create/update guide (e.g., `docs/demos/news_agent_guide.md`) explaining setup and execution.

## Success Metrics (Unchanged)

*   The demo project can be set up and run by following a few clear steps.
*   The code required within the demo project is concise and easy to understand.
*   The agent successfully fetches relevant articles and provides a coherent summary.
*   The demo clearly illustrates how to *use* `adk-ruby` to build agents and custom tools. 
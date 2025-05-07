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
      def execute(params, context = nil)
        topic = params[:topic].downcase
        feed_url = params[:feed_url]
        max_items = params[:max_items]

        ADK.logger.info("#{self.class.name}") { "Fetching feed: #{feed_url} for topic: '#{topic}', max_items: #{max_items}" }

        found_items = []
        begin
          # Open and parse the RSS feed.
          URI.open(feed_url) do |rss|
            feed = RSS::Parser.parse(rss)
            ADK.logger.debug("#{self.class.name}") { "Feed '#{feed.channel.title}' fetched successfully. Items: #{feed.items.size}" }

            feed.items.each do |item|
              title = item.title || ''
              description = item.description || ''

              if title.downcase.include?(topic) || description.downcase.include?(topic)
                ADK.logger.debug("#{self.class.name}") { "Found matching item: #{title}" }
                found_items << {
                  title: title,
                  link: item.link || 'N/A',
                  description: description,
                  published_date: item.pubDate || 'N/A'
                }
              end
              break if found_items.size >= max_items
            end
          end
        rescue RSS::NotWellFormedError => e
          msg = "Failed to parse RSS feed: #{e.message}"
          ADK.logger.error("#{self.class.name}: #{msg} at #{feed_url}")
          raise ADK::ToolError, msg
        rescue StandardError => e # Catch other potential errors (network, etc.)
          msg = "Failed to fetch or process feed: #{e.message}"
          ADK.logger.error("#{self.class.name}: #{msg} at #{feed_url}")
          raise ADK::ToolError, msg
        end

        ADK.logger.info("#{self.class.name}") { "Found #{found_items.size} items matching topic '#{topic}'" }
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
          articles: { type: :array, description: 'An array of article hashes, each with :title, :link, and :description.', required: true }
        }
      )

      # Executes the summarization.
      def execute(params, context = nil)
        articles = params[:articles]
        api_key = ENV['GOOGLE_API_KEY']

        unless api_key
          msg = "GOOGLE_API_KEY environment variable not set."
          ADK.logger.error("#{self.class.name}: #{msg}")
          raise ADK::ToolError, msg
        end

        unless articles.is_a?(Array) && !articles.empty?
          msg = "Invalid or empty 'articles' parameter provided."
          ADK.logger.error("#{self.class.name}: #{msg}")
          raise ADK::ToolArgumentError, msg
        end

        formatted_text = articles.each_with_index.map do |article, index|
          title = article[:title] || article['title'] || 'No Title'
          desc = article[:description] || article['description'] || 'No Description'
          plain_desc = desc.gsub(/<[^>]*>/, ' ').gsub(/\s+/, ' ').strip
          "#{index + 1}. Title: #{title}\n   Description: #{plain_desc[0, 400]}...\n"
        end.join("\n")

        prompt = "Based *only* on the following article titles and descriptions snippets, provide a very concise (1-sentence) summary for each, matching the numbering:\n\n#{formatted_text}"

        ADK.logger.info("#{self.class.name}") { "Sending request to Gemini for #{articles.size} articles." }
        ADK.logger.debug("#{self.class.name}") { "Gemini Prompt Snippet: #{prompt[0, 200]}..." }

        begin
          client = Gemini.new(
            credentials: { service: 'generative-language-api', api_key: api_key },
            options: { model: 'gemini-1.5-flash', server_sent_events: false }
          )

          response_chunks = client.stream_generate_content(
            { contents: { role: 'user', parts: { text: prompt } } }
          )

          if response_chunks.is_a?(Array) && !response_chunks.empty?
            first_candidate = response_chunks.first&.dig('candidates', 0)
            if first_candidate&.dig('finishReason') == 'SAFETY'
              safety_ratings = first_candidate['safetyRatings']
              msg = "Gemini API request blocked due to safety settings. Ratings: #{safety_ratings.inspect}"
              ADK.logger.error("#{self.class.name}: #{msg}")
              raise ADK::ToolError, msg
            end

            llm_summary_text = response_chunks.map do |chunk|
              chunk&.dig('candidates', 0, 'content', 'parts')&.map { |part| part['text'] }&.join
            end.compact.join.strip

            if llm_summary_text.empty?
              msg = "Gemini API returned empty or unparsable summary."
              ADK.logger.error("#{self.class.name}: #{msg} Chunks: #{response_chunks.inspect}")
              raise ADK::ToolError, msg
            end

            ADK.logger.info("#{self.class.name}") { "Received summary text from Gemini." }
            ADK.logger.debug("#{self.class.name}") { "Raw summary text: #{llm_summary_text}" }

            summaries = llm_summary_text.split(/\n\s*(?:\d+\.\s*|\*\s*|-\s*)/).reject(&:empty?).map(&:strip)
            results_array = articles.each_with_index.map do |article, index|
              summary = summaries[index] || "(Summary not generated)"
              {
                title: article[:title] || article['title'],
                link: article[:link] || article['link'] || '#',
                summary: summary
              }
            end
            results_array = results_array.first(articles.size)
            { status: :success, result: results_array }
          else
            msg = "Gemini API returned unexpected response format."
            ADK.logger.error("#{self.class.name}: #{msg} Response: #{response_chunks.inspect}")
            raise ADK::ToolError, msg
          end

        rescue Gemini::Errors::RequestError => e
          msg = "Gemini API request error: #{e.message}"
          ADK.logger.error("#{self.class.name}: #{msg} Payload: #{e.try(:payload).inspect}")
          raise ADK::ToolError, msg
        rescue Faraday::Error => e # Catch Faraday connection errors
          msg = "Network error communicating with Gemini API: #{e.message}"
          ADK.logger.error("#{self.class.name}: #{msg}")
          raise ADK::ToolError, msg
        rescue StandardError => e
          msg = "Failed to summarize articles: #{e.message}"
          ADK.logger.error("#{self.class.name}: Error calling Gemini API: #{e.class} - #{msg}")
          ADK.logger.error(e.backtrace.first(5).join("\n"))
          raise ADK::ToolError, msg
        end
      end
    end
    ```
6. **Runner Script:** Create `adk-news-demo/run_news_agent.rb`:
    ```ruby
    require 'bundler/setup'
    require 'adk' # Load the ADK gem
    require 'dotenv'
    # Tool requires are now handled automatically by ADK::Agent via tool_paths

    # Load .env file from demo project
    Dotenv.load

    # Configure ADK (optional, if defaults aren't sufficient)
    # ADK.configure do |config|
    #   config.log_level = :INFO
    # end

    # --- 1. Define the Agent ---
    # Agent initialization now automatically discovers tools in the specified path
    agent = ADK::Agent.new(
      name: 'news_agent',
      description: 'Fetches and summarizes news from RSS feeds.',
      tool_paths: './tools' # Specify the directory containing tool definitions
      # model_name: 'gemini-pro' # Optional: If different from default
    )

    # --- Tool instances are now automatically added during agent initialization ---

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
    puts "\n-------------------- AGENT RESPONSE --------------------"
    require 'json' # Keep require for potential plan_details debugging

    agent_event = result_event # Rename for clarity
    agent_content = agent_event.content

    if agent_content[:status] == :success
      puts "✅ Agent Task Succeeded!"

      # --- Workaround: Fetch the session object and access its events ---
      retrieved_session = session_service.get_session(session_id: session.id) # Use the original session_id with keyword arg
      unless retrieved_session
        puts "\n⚠️ Error: Could not retrieve session #{session.id} after task execution."
        # Handle error appropriately, maybe exit
        exit(1)
      end

      all_events = retrieved_session.events # Assuming the attribute is named :events
      unless all_events.is_a?(Array)
        puts "\n⚠️ Error: Session object does not have an accessible :events array."
        puts "   Session Object: #{retrieved_session.inspect}"
        # Handle error appropriately, maybe exit
        exit(1)
      end

      last_tool_name_str = (agent_content.dig(:plan_details, -1, :tool_name) || :summarizer).to_s

      last_tool_result_event = all_events.reverse.find do |event|
        # Revert to checking event.tool_name
        event && event.role == :tool_result && event.tool_name&.to_s == last_tool_name_str
      end

      if last_tool_result_event
        # Assign the whole content hash, not just the nested :result
        last_tool_result_hash = last_tool_result_event.content

        if last_tool_result_hash.is_a?(Hash) && last_tool_result_hash[:status] == :success && last_tool_result_hash[:result].is_a?(Array)
          puts "\n📰 Here's your news summary:"
          puts "--------------------------------------------------------"
          last_tool_result_hash[:result].each do |item|
            puts "🔹 Title: #{item[:title]}"
            puts "   Link: #{item[:link]}"
            puts "   Summary: #{item[:summary]}"
            puts "--------------------------------------------------------"
          end
        else
          # Handle cases where the raw tool result event shows an error or unexpected format
          tool_name_str = last_tool_result_event.content[:tool_name] || '?'
          status_str = last_tool_result_hash.is_a?(Hash) ? last_tool_result_hash[:status] : 'N/A'
          message_str = if last_tool_result_hash.is_a?(Hash)
                          last_tool_result_hash[:error_message] || last_tool_result_hash[:result] || '(No specific message)'
                        else
                          last_tool_result_hash.inspect
                        end

          puts "\n⚠️ Agent finished, but the final tool step (#{tool_name_str}) reported an issue (found via raw event):"
          puts "   Status: #{status_str}"
          puts "   Message: #{message_str}"
          puts "--------------------------------------------------------"
        end
      else
        # Fallback if the specific tool_result event couldn't be found
        puts "\nℹ️ Agent finished successfully, but couldn't find the raw result event for the last tool (#{last_tool_name_str})."
        puts "   Checking event history (#{all_events.size} events):"
        # Update debug print to use evt.tool_name
        all_events.each_with_index do |evt, idx|
          puts "     [#{idx}] Role: #{evt&.role}, Tool: #{evt&.tool_name&.inspect}"
        end
        puts "   Top-Level Agent Result: #{agent_content[:result].inspect}"
        puts "--------------------------------------------------------"
      end
      # --- End Workaround ---

      # Uncomment below to see the full execution plan details from the *agent* event (may contain stringified results):
      # if agent_content[:plan_details]
      #   puts "\n--- Plan Details ---"
      #   puts JSON.pretty_generate(agent_content[:plan_details])
      # end
    else
      puts "❌ Error!"
      error_message = agent_content[:error_message] || "An unknown error occurred."
      puts "Error Message: #{error_message}"
      # Optionally print the full event for detailed debugging on error
      # puts "\n--- Full Error Event ---"
      # puts JSON.pretty_generate(result_event.to_h)
    end
    puts "--------------------------------------------------------\n"
    ```
7. **Environment Setup:** Create `.env` file in `adk-news-demo/` with your API key and desired log level:
   ```dotenv
   GOOGLE_API_KEY=your_actual_google_api_key_here
   ADK_LOG_LEVEL=INFO # Or DEBUG, WARN, ERROR, FATAL
   ```
8. **Testing:** Navigate to `adk-news-demo/` and run `bundle exec ruby run_news_agent.rb`. Verify the output includes a summary.
9. **Documentation (in `adk-ruby` repo):** Create/update guide (e.g., `docs/demos/news_agent_guide.md`) explaining setup and execution.

## Success Metrics (Unchanged)

*   The demo project can be set up and run by following a few clear steps.
*   The code required within the demo project is concise and easy to understand.
*   The agent successfully fetches relevant articles and provides a coherent summary.
*   The demo clearly illustrates how to *use* `adk-ruby` to build agents and custom tools. 
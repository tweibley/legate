# Plan: Refactor lib/adk/web/app.rb

This document outlines the plan to refactor the main Sinatra application file (`lib/adk/web/app.rb`) by splitting its routes into smaller, more manageable modules based on functional areas.

## 1. Goal

The primary goal is to improve the organization, readability, and maintainability of the ADK Web UI's main application file. A secondary goal is to establish a pattern for how new web functionalities and their routes can be added in a modular fashion.

## 2. Strategy: Sinatra Extensions (Modules)

We will use Sinatra's extension mechanism, which involves:
*   Creating separate Ruby modules for different sets of routes.
*   Each module will contain a `self.registered(app)` method where routes are defined using the passed `app` instance.
*   The main `ADK::Web::App` class will then `require` these modules and `register` them.
*   Helper methods and instance variables defined in the main `ADK::Web::App` will remain accessible to the routes within these registered modules.

*(Note: This strategy aligns with the recommended practices for extending modular Sinatra applications as per the official Sinatra documentation. The use of `register YourModule` within the `Sinatra::Base` subclass and defining routes within the `self.registered(app)` method is the standard approach.)*

## 3. Detailed Steps

### Step 3.1: Create Directory Structure

Create a new directory to house the route modules:
*   `lib/adk/web/routes/`

### Step 3.2: Identify Functional Areas and Create Route Modules

We will create the following module files within `lib/adk/web/routes/`. Each file will define a module (e.g., `ADK::Web::CoreRoutes`) containing the `self.registered(app)` method, into which the corresponding routes from `app.rb` will be moved.

1.  **`core_routes.rb`**: For basic application routes. **[DONE]**
    *   Module: `ADK::Web::CoreRoutes`
    *   Routes:
        *   `GET /`
        *   `GET /healthz`

2.  **`agent_definition_routes.rb`**: For routes related to agent definition management (CRUD, display, edit forms). **[DONE]**
    *   Module: `ADK::Web::AgentDefinitionRoutes`
    *   Routes:
        *   `GET /agents` (main agent management page)
        *   `POST /agents` (create new agent definition)
        *   `DELETE /agents/:name` (delete agent definition)
        *   `GET /agents/:name` (display agent detail page)
        *   `GET /agents/:name/edit/:field` (show edit form for a field)
        *   `PUT /agents/:name/update/:field` (process update for a field)
        *   `GET /agents/:name/display/:field` (show display partial for a field)
        *   `GET /agents/:name/display/tool_table` (show tool table display partial)

3.  **`agent_runtime_routes.rb`**: For routes controlling the runtime state of agents. **[DONE]**
    *   Module: `ADK::Web::AgentRuntimeRoutes`
    *   Routes:
        *   `POST /agents/:name/start/detail` (start agent from detail view)
        *   `POST /agents/:name/stop/detail` (stop agent from detail view)
        *   `POST /agents/:name/start` (start agent from main list view)
        *   `POST /agents/:name/stop` (stop agent from main list view)
        *   *(Note: The existing `_start_agent` and `_stop_agent` private methods in `app.rb` will be called by these routes. They can be called using `app.send(:_start_agent, name)` from within the module's route block.)*

4.  **`agent_interaction_routes.rb`**: For routes handling user interaction with agents (chat, direct execution).
    *   Module: `ADK::Web::AgentInteractionRoutes`
    *   Routes:
        *   `GET /agents/:name/chat` (display chat interface)
        *   `POST /agents/:name/chat` (process chat message)
        *   `POST /agents/:name/execute` (direct task execution)
        *   `GET /agents/:name/generate_example_task` (generate example task JSON)

5.  **`tools_ui_routes.rb`**: For routes related to displaying tool information. **[DONE]**
    *   Module: `ADK::Web::ToolsUIRoutes`
    *   Routes:
        *   `GET /tools` (display available native tools page)
        *   `GET /tools/:name` (display tool detail page)

6.  **`api_routes.rb`**: For JSON API endpoints. **[DONE]**
    *   Module: `ADK::Web::ApiRoutes`
    *   Routes:
        *   `GET /api/agents`
        *   `GET /api/tools`

### Step 3.3: Structure of Route Module Files

Each file (e.g., `lib/adk/web/routes/core_routes.rb`) will look similar to this:

```ruby
# File: lib/adk/web/routes/core_routes.rb
# frozen_string_literal: true

module ADK
  module Web
    module CoreRoutes
      def self.registered(app)
        # Example route:
        app.get '/' do
          # logger is available via app.logger or directly if helpers are mixed in
          # instance variables like @definition_store via app.instance_variable_get(:@definition_store)
          # or by ensuring main app's context is available.
          # Sinatra helpers defined in the main app are directly available.
          app.logger.debug("GET / route handler from CoreRoutes module entered")
          app.slim :index # app.slim to call slim from the main app instance
        end

        app.get '/healthz' do
          # ... healthz logic ...
        end

        # ... other routes for this module ...
      end
    end
  end
end
```
*Accessing Instance Variables*: Instance variables from the main `App` class (like `@definition_store`, `@agents`, `@logger`, `@session_service`) can be accessed within the route blocks using `app.instance_variable_get(:@variable_name)` or by delegating methods if preferred. `app.logger` should work directly.
*Accessing Helpers*: Sinatra helpers defined in the main `App` class (within `helpers do ... end`) should be directly available within the route blocks in the registered modules. Private methods like `_start_agent` in the main app can be called using `app.send(:_start_agent, name)`.

### Step 3.4: Modify `lib/adk/web/app.rb`

1.  **Remove Moved Routes**: Delete all the route definitions that have been moved to the new module files from `app.rb`.
    *   `GET /` and `GET /healthz` removed. **[DONE for CoreRoutes]**
    *   `GET /api/agents` and `GET /api/tools` removed. **[DONE for ApiRoutes]**
    *   `GET /tools` and `GET /tools/:name` removed. **[DONE for ToolsUIRoutes]**
    *   `POST /agents/:name/start/detail`, `POST /agents/:name/stop/detail`, `POST /agents/:name/start`, `POST /agents/:name/stop` removed. **[DONE for AgentRuntimeRoutes]**
    *   All 8 agent definition routes (CRUD, edit, display) removed. **[DONE for AgentDefinitionRoutes]**
2.  **Keep Core Configuration**: Retain Sinatra settings (`set :root`, etc.), `configure` blocks, `helpers do ... end` block, `initialize` method, and private helper methods (`_start_agent`, `_stop_agent`) in `app.rb`.
3.  **Require Route Modules**: Add `require_relative` statements for each new route module file near the top of `app.rb`, after other primary requires.
    ```ruby
    # ... other requires ...
    require_relative 'routes/core_routes' # [DONE]
    require_relative 'routes/agent_definition_routes' # [DONE]
    require_relative 'routes/api_routes' # [DONE]
    require_relative 'routes/tools_ui_routes' # [DONE]
    require_relative 'routes/agent_runtime_routes' # [DONE]
    require_relative 'routes/agent_interaction_routes'
    # ... etc. for all route modules
    ```
4.  **Register Modules**: Inside the `ADK::Web::App` class definition, register each module:
    ```ruby
    class App < Sinatra::Base
      # ... existing configure blocks, helpers, initialize ...

      register ADK::Web::CoreRoutes # [DONE]
      register ADK::Web::AgentDefinitionRoutes # [DONE]
      register ADK::Web::AgentRuntimeRoutes # [DONE]
      register ADK::Web::AgentInteractionRoutes
      register ADK::Web::ToolsUIRoutes # [DONE]
      register ADK::Web::ApiRoutes # [DONE]

      # ... private methods like _start_agent, _stop_agent ...
    end
    ```

## 4. Order of Refactoring (Recommended)

It's advisable to refactor one module at a time to isolate potential issues:
1.  Start with a small, less complex module (e.g., `CoreRoutes` or `ApiRoutes`). **[CoreRoutes implemented and tested successfully]**
2.  Create the module file, move the routes. **[ApiRoutes implemented and tested successfully]**
3.  Update `app.rb` to require and register this module. **[ToolsUIRoutes implemented and tested successfully]**
4.  Thoroughly test the moved routes. **[AgentRuntimeRoutes implemented and tested successfully]**
5.  Repeat for each subsequent module. **[AgentDefinitionRoutes implemented - PENDING TESTING]**

## 5. Testing Strategy

*   **After each module is refactored**:
    *   Manually test all routes moved to that module by navigating the web UI and using tools like `curl` for API endpoints.
    *   Check for any broken functionality, incorrect responses, or errors in the server logs.
    *   Verify that pages render correctly and HTMX interactions still work as expected.
*   **After all modules are refactored**:
    *   Perform a full regression test of the entire web application.

## 6. Potential Challenges & Considerations

*   **Context and Scope**: Ensure that instance variables, helpers, and logger from the main `app` instance are correctly accessed within the modules. The `app` object passed to `registered` and available in route blocks is the key.
*   **Route Clashes**: Unlikely if routes are simply moved, but double-check that no route definitions are inadvertently duplicated.
*   **Dependencies Between Routes**: If routes in one module redirect to or trigger HTMX swaps that are handled by routes in another module, ensure these interactions remain seamless. This is generally handled well by Sinatra.
*   **Private Method Access**: Confirm that private methods like `_start_agent` and `_stop_agent` can be successfully called from the modules using `app.send(:method_name, args)`.

This refactoring will set a solid foundation for future development and make the codebase easier to manage. 
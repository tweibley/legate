# Plan: Multi-Session Chat per Agent

This document outlines the plan to implement a feature allowing users to have multiple distinct chat sessions with the same agent in the ADK Web UI. Users will be able to start new sessions and switch between existing ones.

## 1. Core Requirements

*   **User Identification:** A consistent way to identify a web user across their browser session.
*   **Session Listing:** Users should be able to see a list of their previous chat sessions with the current agent.
*   **Session Switching:** Users should be able to switch to any of their previous chat sessions with the current agent.
*   **New Session Creation:** Users should be able to explicitly start a new, clean chat session with the current agent.
*   **Persistence:** The active session and the list of available sessions for an agent should be maintained for the user.

## 2. Backend Changes

### 2.1. `ADK::Session` (lib/adk/session.rb)

*   **No changes currently anticipated.** The class already contains:
    *   `id` (String): Unique session ID.
    *   `app_name` (String): Agent name.
    *   `user_id` (String): User identifier.
    *   `created_at` (Time): Timestamp of creation.
    *   `updated_at` (Time): Timestamp of last update.
    *   `events` (Array<ADK::Event>): History of interactions.

### 2.2. `ADK::SessionService::InMemory` (lib/adk/session_service/in_memory.rb)

*   **No changes currently anticipated.** The class already supports:
    *   `create_session(app_name:, user_id:, initial_state: {})`: Creates a session.
    *   `get_session(session_id:)`: Retrieves a session.
    *   `list_sessions(app_name: nil, user_id: nil)`: Lists sessions, filterable by `app_name` and `user_id`. This is key for the new feature.

### 2.3. Sinatra Application (`lib/adk/web/app.rb`)

*   **User ID Management (Web UI Specific):**
    *   Implement as a `before '/agents/:name/chat*'` filter.
    *   Inside the filter: `session[:web_user_id] ||= SecureRandom.uuid`.

*   **Sinatra Session Storage for Active ADK Session:**
    *   The current `session[:adk_sessions][agent_name]` stores *the* ADK session ID for an agent. This will be repurposed to store the *currently active* ADK session ID for that agent and the current `session[:web_user_id]`.
    *   The structure might look like: `session[:active_adk_sessions][web_user_id][agent_name] = "active_adk_session_id"`. This ensures that if multiple browser users hit the same Sinatra instance, their active sessions don't collide. For simplicity in a single-user dev context, `session[:active_adk_sessions_for_agent][agent_name]` might suffice if `web_user_id` is used primarily for `session_service` calls. Let's refine this:
        *   We will use `session[:web_user_id]` to identify the user for `@session_service` calls.
        *   For storing the *active* ADK session ID for a *specific agent* for *that user*, we can use a nested structure in the Sinatra session:
            `session[:active_agent_sessions] ||= {}`
            `session[:active_agent_sessions][agent_name] = "current_adk_session_id_for_this_agent_and_web_user"`

*   **Modify `GET /agents/:name/chat` Route:**
    1.  **Establish `web_user_id`:** Ensure `session[:web_user_id]` is set.
    2.  **Determine Active ADK Session ID:**
        *   Check for a `?desired_session_id=` query parameter. If present, attempt to fetch the session using this ID. If the fetched session belongs to the current `session[:web_user_id]` and `agent_name` (validated by checking ownership), make it active. If the `desired_session_id` is not provided, is invalid (cannot be fetched), or does not belong to the current user/agent, this parameter is ignored, and the system proceeds to the next step to determine the active session. (Optional: if an invalid/unowned `desired_session_id` was provided, a message can be displayed to the user, e.g., "Could not switch to the requested session, loading the latest active session instead.")
        *   Else, check `session[:active_agent_sessions][agent_name]`. If valid (exists and session can be fetched), use it.
        *   Else, fetch all sessions for `web_user_id` and `agent_name` using `@session_service.list_sessions`.
            *   If sessions exist, sort them by `updated_at` descending and make the first one (most recently updated) active.
        *   Store the determined active ADK session ID in `session[:active_agent_sessions][agent_name]`.
    3.  **Load Active Session History:** Fetch events for the active ADK session ID using `@session_service.get_session`. If the session can't be loaded (e.g., ID is stale), clear `session[:active_agent_sessions][agent_name]` and re-run logic from step 2 (or create new).
    4.  **Load All Previous Sessions for this Agent/User:**
        *   Use `@session_service.list_sessions(app_name: name, user_id: session[:web_user_id])`.
        *   Sort them (e.g., by `updated_at` descending).
        *   Prepare a summarized version of each session for display (e.g., ID, created_at, first few words of the first user message).
    5.  **Pass Data to View:**
        *   `@active_session_details` (e.g., the `ADK::Session` object or its relevant parts).
        *   `@chat_history_events` (from the active session).
        *   `@previous_sessions_list` (summarized list for selection).
        *   `@agent_data` (as currently).

*   **Modify `POST /agents/:name/chat` Route:**
    1.  **Establish `web_user_id`:** Ensure `session[:web_user_id]` is set.
    2.  **Retrieve Active ADK Session ID:** Get it from `session[:active_agent_sessions][agent_name]`.
    3.  **Error Handling:** If no active session ID is found (shouldn't happen if `GET` logic is correct), handle appropriately (e.g., redirect to `GET /agents/:name/chat` to establish one).
    4.  Use this active ADK session ID when calling `@agent.run_task`.

*   **New Route: `POST /agents/:name/chat/session/new`**
    1.  **Establish `web_user_id`:** (Handled by `before` filter).
    2.  Create a new session: `new_adk_session = @session_service.create_session(app_name: name, user_id: session[:web_user_id])`.
    3.  Update the active session ID: `session[:active_agent_sessions][agent_name] = new_adk_session.id`.
    4.  If `request.env['HTTP_HX_REQUEST'] == 'true'`, render an HTML fragment targeting `#chat_interface_wrapper` (see section 3.1 for structure). Otherwise, redirect to `GET /agents/:name/chat`.

*   **New Route: `POST /agents/:name/chat/session/switch` (preferred over GET with query param for session changing actions)**
    1.  **Establish `web_user_id`:** (Handled by `before` filter).
    2.  Get `params[:adk_session_to_switch_to]`.
    3.  **Validation:** Crucially, verify that this `adk_session_to_switch_to` actually belongs to the current `session[:web_user_id]` and `agent_name` by fetching it via `@session_service.get_session` and checking its `user_id` and `app_name`. This prevents users from accessing others' sessions. If invalid, handle error (see User-Friendly Error Display in Considerations).
    4.  If valid, update active session: `session[:active_agent_sessions][agent_name] = params[:adk_session_to_switch_to]`.
    5.  If `request.env['HTTP_HX_REQUEST'] == 'true'`, render an HTML fragment targeting `#chat_interface_wrapper`. Otherwise, redirect to `GET /agents/:name/chat`.
    *   The `GET /agents/:name/chat` route will still check `?desired_session_id=` for initial deep linking but POST is preferred for explicit user actions.

*   **(Optional) New Route: `DELETE /agents/:name/chat/session/:adk_session_id_to_delete`**
    1.  **Establish `web_user_id`:** (Handled by `before` filter).
    2.  **Validation:** Verify the `adk_session_id_to_delete` belongs to the current `session[:web_user_id]` and `agent_name`. This is a critical security check. If invalid, handle error.
    3.  Call `@session_service.delete_session(session_id: adk_session_id_to_delete)`.
    4.  If the deleted session was the active one (`session[:active_agent_sessions][agent_name] == adk_session_id_to_delete`), clear `session[:active_agent_sessions][agent_name]`. Then, attempt to set a new active session by finding the most recently updated session for the current user/agent from the remaining sessions. If other sessions exist, its ID is stored in `session[:active_agent_sessions][agent_name]`. If no other sessions exist, this key will remain unset (which would lead to a new session being created on the next `GET /agents/:name/chat` if the user stays on the page or if the redirect leads there).
    5.  Redirect or use HTMX.

## 3. Frontend Changes (Slim Templates)

### 3.1. `lib/adk/web/views/chat.slim`

*   **Overall Structure:** The main content of `chat.slim` should be wrapped in a `div id="chat_interface_wrapper"`. This div is the primary target for HTMX swaps when sessions change or new messages arrive, ensuring the entire chat context (session list, active session info, messages) is refreshed.
*   **Layout (Conceptual - Desktop First):**
    *   Inside `#chat_interface_wrapper`:
        *   `div class="columns"`
            *   `div class="column is-one-third" id="chat_session_sidebar"`
                *   Section title: "Chat Sessions"
                *   "Start New Chat" Button (POST to `/agents/:name/chat/session/new`, `hx-target="#chat_interface_wrapper"`)
                *   `div id="session-operation-error" class="notification is-danger is-hidden"` (For displaying errors from session operations).
                *   List of previous sessions (`@previous_sessions_list`):
                    *   Each item: `div class="session-list-item"` (add `is-active` class if it's the current `@active_session_details.id`).
                        *   Display summary from `summarize_session(session)` helper.
                        *   "Switch" button/form (POST to `/agents/:name/chat/session/switch` with `adk_session_to_switch_to=session.id`, `hx-target="#chat_interface_wrapper"`).
            *   `div class="column is-two-thirds" id="chat_main_panel"`
                *   Agent Name & Description (`@agent_data`).
                *   Active session info (e.g., "Chatting since: [timestamp]") from `@active_session_details`.
                *   Chat messages log (`#chat-log-container` - current HTMX target for new messages can remain within this panel).
                *   Message input form.
*   **Session Management Section (Detailed):**
    *   The `#chat_session_sidebar` will contain:
        *   Information about the `@active_session_details` (e.g., "Active Session started: [timestamp]"). It must be clear which session in the list is the active one.
        *   Clearly handle the "no previous sessions" state (e.g., by showing "No previous chats with this agent yet." below the "Start New Chat" button).
        *   **"Start New Chat" Button:** As described above.
        *   **Previous Sessions List:** As described above, ensuring the active session is visually highlighted.

### 3.2. Helper for Session Summary

*   In `lib/adk/web/app.rb` helpers:
    *   Create a helper method `summarize_session(session_object)` that takes an `ADK::Session` and returns a string like "Chat from [formatted_created_at] (Last active: [formatted_updated_at]) ([N] messages): [preview text]". The preview text should be the first ~10 words of the first user-initiated text event's message, or 'Empty session' if no such events, or 'Session started [timestamp]' if no events at all. It should gracefully handle sessions with no user messages or only non-text initial messages. The count `session_object.events.count` can be used for N.

## 4. Implementation Checklist

**Phase 1: Backend Foundation**

*   [x] **Web User ID:** Implement `before '/agents/:name/chat*'` filter for `session[:web_user_id]`.
*   [x] **Active ADK Session Store:** Modify Sinatra session to store the active ADK session ID per agent for the `web_user_id` (e.g., `session[:active_agent_sessions][agent_name]` established in GET route).
*   [x] **`GET /agents/:name/chat` - Core Logic:**
    *   [x] Integrate `session[:web_user_id]`.
    *   [x] Implement logic to determine/set the active ADK session ID using `session_service.list_sessions` (sorted by `updated_at` desc) and `session_service.create_session` as fallback.
    *   [x] Add robust error handling if active session ID is stale/invalid (re-evaluate active session).
    *   [x] Ensure active ADK session ID is stored in Sinatra session.
    *   [x] Load active session history.
    *   [x] Load list of all previous sessions for the agent/user.
*   [x] **`POST /agents/:name/chat` - Core Logic:**
    *   [x] Integrate `session[:web_user_id]`.
    *   [x] Use the stored active ADK session ID.
    *   [x] Add error handling if no active session ID is found (e.g., redirect to `GET /agents/:name/chat` to establish one).
*   [x] **Route: `POST /agents/:name/chat/session/new`:**
    *   [x] Implement creation of new ADK session.
    *   [x] Update active ADK session ID in Sinatra session.
    *   [x] Implement redirect/HTMX reload trigger.
*   [x] **Route: Session Switching (e.g., `GET /agents/:name/chat?desired_session_id=:id` or `POST /agents/:name/chat/session/switch`):**
    *   [x] Implement logic to switch active ADK session ID.
    *   [x] Crucial: Add validation to ensure session belongs to the current user and agent.
    *   [x] Implement redirect/HTMX reload trigger.

**Phase 2: Frontend Integration**

*   [x] **`lib/adk/web/app.rb` - Session Summary Helper:** Create `summarize_session` helper (include event count).
*   [x] **`lib/adk/web/views/chat.slim` - Overall Structure:** Implement `#chat_interface_wrapper` and conceptual layout (sidebar, main panel).
*   [x] **`lib/adk/web/views/chat.slim` - Display Active Session Info:** Show details of `@active_session_details` in the main panel and highlight in sidebar.
*   [x] **`lib/adk/web/views/chat.slim` - "Start New Chat" Button:**
    *   [x] Add button.
    *   [x] Wire up HTMX POST to the new session route.
*   [ ] **`lib/adk/web/views/chat.slim` - Previous Sessions List:**
    *   [ ] Iterate and display summarized previous sessions (using helper).
    *   [ ] Clearly indicate the currently active session in the list (e.g., `is-active` class).
    *   [ ] Handle the "no previous sessions" UI state.
    *   [ ] Add "Switch" buttons/forms with HTMX targeting `#chat_interface_wrapper`.

**Phase 3: Refinements & Optional Features**

*   [ ] **UI/UX:** Polish the appearance and interaction of the session management UI. Consider responsive behavior for the sidebar on smaller screens.
*   [ ] **Error Handling:** Robust error handling for invalid session IDs, etc., with user-friendly messages displayed in `#session-operation-error` via HTMX swaps from error partials.
*   [ ] **(Optional) Route: `DELETE /agents/:name/chat/session/:adk_session_id_to_delete`:** Implement if desired.
*   [ ] **Testing:** Thoroughly test session creation, switching, message posting within switched sessions, and user isolation.
*   **HTMX Swaps:** Primary HTMX target for session changes is `#chat_interface_wrapper`. Individual new messages can still target a more specific `#chat-log-container` within the main panel.
*   **User-Friendly Error Display:** Backend routes should, on error during an HTMX request, return an HTML partial (e.g., `_session_error.slim` containing the error message wrapped in a notification div) that is swapped into the `#session-operation-error` div in the sidebar. For non-HTMX errors, use standard flash messages or error pages.

This plan provides a comprehensive roadmap. Each checklist item can be broken down further during implementation. 

## 6. New Tests (Specs) Needed

We'll primarily need request specs for the Sinatra application (`spec/adk/web/app_spec.rb` or a new `spec/adk/web/chat_session_spec.rb`) and potentially unit tests for the new helper.

### 6.1. Request Specs (`ADK::Web::App`)

*   **User ID Management:**
    *   `session[:web_user_id]` is created on the first relevant request (e.g., to `/agents/:name/chat`).
    *   `session[:web_user_id]` persists across subsequent requests from the same client.
*   **`GET /agents/:name/chat`:**
    *   **New User/Agent Interaction:**
        *   A new `ADK::Session` is created via `@session_service` with the correct `app_name` and `session[:web_user_id]`.
        *   The ID of this new session is stored in `session[:active_agent_sessions][agent_name]`.
        *   `@active_session_details` reflects this new session.
        *   `@previous_sessions_list` is empty or contains only this new session.
    *   **Existing Active Session in Sinatra Session:**
        *   If `session[:active_agent_sessions][agent_name]` points to a valid session for the user/agent, that session's data is loaded.
    *   **No Active Session in Sinatra, but Previous Sessions Exist:**
        *   `@session_service.list_sessions` is called for the user/agent.
        *   The most recently updated session becomes active and its ID is stored.
    *   **`?desired_session_id=` Query Parameter:**
        *   If `desired_session_id` is valid and belongs to the user/agent, it becomes the active session.
        *   If `desired_session_id` is invalid or doesn't belong to the user/agent, it is ignored, and the system falls back to the standard logic (load existing active session from Sinatra session, or load latest from all user/agent sessions, or create new). A user-facing message might be optionally displayed to indicate the requested session was not loaded.
    *   `@previous_sessions_list` is correctly populated, sorted, and contains summarized data.
    *   `@chat_history_events` correctly reflects the events of the active session.
*   **`POST /agents/:name/chat` (Message Sending):**
    *   Messages are correctly appended to the ADK session identified by `session[:active_agent_sessions][agent_name]` for the current `session[:web_user_id]`.
    *   It handles cases where no active session is set (should ideally redirect to `GET /chat` to establish one).
*   **`POST /agents/:name/chat/session/new`:**
    *   A new `ADK::Session` is created with the correct `app_name` and `session[:web_user_id]`.
    *   The new session's ID becomes the value in `session[:active_agent_sessions][agent_name]`.
    *   The response correctly redirects or triggers the appropriate HTMX reload.
*   **`POST /agents/:name/chat/session/switch` (or GET with query param):**
    *   The active session in `session[:active_agent_sessions][agent_name]` is updated to the `params[:adk_session_to_switch_to]`.
    *   **Security:** Fails (e.g., 403 Forbidden or 404 Not Found) if `adk_session_to_switch_to` does not belong to `session[:web_user_id]` and `agent_name`.
    *   The response correctly redirects or triggers HTMX.
*   **(Optional) `DELETE /agents/:name/chat/session/:id_to_delete`:**
    *   Successfully deletes a session owned by the user/agent.
    *   Fails if the session is not owned.
    *   Handles making another session active if the deleted one was active.

### 6.2. Helper Specs (e.g., in `spec/adk/web/app_helpers_spec.rb`)

*   **`summarize_session(session_object)` helper:**
    *   Correctly formats `created_at`.
    *   Correctly formats and includes `updated_at` (if this part of the summary is implemented).
    *   Correctly displays the event count `N`.
    *   Extracts the first ~10 words of the first user-initiated text event's message.
    *   Handles sessions with no user events (returns "Empty session" or similar, based on the defined logic).
    *   Handles sessions with no events at all (returns "Session started [timestamp]" or similar).
    *   Handles events where the first user message might not have simple text content (if possible). 
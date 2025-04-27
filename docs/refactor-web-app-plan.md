# Refactoring Plan: Agent Definition Persistence in Web App

## Goal

Eliminate direct Redis calls from `lib/adk/web/app.rb` for managing agent definitions. Introduce a dedicated persistence abstraction layer within the core ADK library to handle these operations, making the web app independent of the specific storage mechanism (Redis).

## Current State

The `ADK::Web::App` class in `lib/adk/web/app.rb` currently uses an instance variable `@redis` (a direct `Redis` client connection) for all operations related to agent definitions:
*   Storing agent configurations (description, tools, model, fallback, MCP servers) in Hashes (`adk:agent:<name>`).
*   Managing the set of all agent names (`adk:agents:all_names`).
*   Retrieving, updating, and deleting these definitions.
*   Checking Redis connectivity (`ping`).

This approach tightly couples the web application to Redis and mixes persistence logic with web request handling.

## Proposed Solution

1.  **Introduce a Persistence Abstraction:** Create a new module or service within the core ADK library dedicated to agent definition persistence. Let's call it `ADK::DefinitionStore`.
2.  **Implement Redis Store:** Create a concrete implementation using Redis within the new module: `ADK::DefinitionStore::RedisStore`. This class will encapsulate all the Redis-specific logic.
3.  **Define Store Interface:** The `RedisStore` (and potentially a base module/class) will define methods for all necessary persistence operations.
4.  **Refactor Web App:** Modify `ADK::Web::App` to:
    *   Instantiate and use the `ADK::DefinitionStore::RedisStore` instead of the direct `@redis` client.
    *   Replace all direct `@redis` calls related to agent definitions with calls to the new store's methods.

## Task List

### Phase 1: Create ADK Definition Store

*   [ ] Create file structure: `lib/adk/definition_store/`
*   [ ] Create base module file: `lib/adk/definition_store.rb`
*   [ ] Create Redis implementation file: `lib/adk/definition_store/redis_store.rb`
*   [ ] Implement `ADK::DefinitionStore::RedisStore#initialize(redis_client)`:
    *   Takes a configured Redis client instance.
    *   Stores Redis client internally.
    *   Defines constants for Redis key prefixes/names.
*   [ ] Implement `ADK::DefinitionStore::RedisStore#save_definition(name:, description:, tools:, model:, fallback_mode:, mcp_servers_json:)`:
    *   Takes agent definition data as arguments or a hash.
    *   Validates required fields (e.g., name).
    *   Uses Redis `MULTI` transaction.
    *   Serializes tools array and MCP config to JSON.
    *   Uses `HSET` to store fields in `adk:agent:<name>`.
    *   Uses `SADD` to add name to `adk:agents:all_names`.
    *   Returns success/failure or the created definition ID/name.
*   [ ] Implement `ADK::DefinitionStore::RedisStore#get_definition(agent_name)`:
    *   Takes agent name.
    *   Uses `HMGET` to retrieve all fields from `adk:agent:<name>`.
    *   Deserializes tools JSON and MCP JSON.
    *   Handles missing agent (returns `nil`).
    *   Returns a structured hash representing the definition (or potentially a dedicated `AgentDefinition` object/struct in the future).
*   [ ] Implement `ADK::DefinitionStore::RedisStore#update_definition(agent_name, updates_hash)`:
    *   Takes agent name and a hash of fields/values to update.
    *   Serializes specific fields (tools, mcp) to JSON if present in updates.
    *   Uses `HSET` (potentially in `MULTI` if multiple fields) to update `adk:agent:<name>`.
    *   Returns success/failure.
*   [ ] Implement `ADK::DefinitionStore::RedisStore#delete_definition(agent_name)`:
    *   Takes agent name.
    *   Uses Redis `MULTI` transaction.
    *   Uses `DEL` to remove `adk:agent:<name>`.
    *   Uses `SREM` to remove name from `adk:agents:all_names`.
    *   Returns success/failure or number of keys affected.
*   [ ] Implement `ADK::DefinitionStore::RedisStore#list_definitions()`:
    *   Uses `SMEMBERS` to get all names from `adk:agents:all_names`.
    *   If names exist, uses pipelined `HMGET` to fetch essential fields (e.g., name, description, model) for each agent.
    *   Returns an array of hashes, each representing an agent summary.
*   [ ] Implement `ADK::DefinitionStore::RedisStore#definition_exists?(agent_name)`:
    *   Takes agent name.
    *   Uses `SISMEMBER` on `adk:agents:all_names`.
    *   Returns `true` or `false`.
*   [ ] Implement `ADK::DefinitionStore::RedisStore#check_connection()`:
    *   Uses `PING` on the internal Redis client.
    *   Returns `true` on success, raises or returns `false` on failure.
*   [ ] Add unit tests for `ADK::DefinitionStore::RedisStore` (requires mocking the Redis client).

### Phase 2: Refactor Web Application (`lib/adk/web/app.rb`)

*   [ ] Modify `ADK::Web::App#initialize`:
    *   Remove direct `@redis = Redis.new`.
    *   Instantiate `redis_client = Redis.new`.
    *   Instantiate `@definition_store = ADK::DefinitionStore::RedisStore.new(redis_client)`.
    *   Handle Redis connection errors gracefully (store `nil` in `@definition_store` or use a Null Object pattern).
    *   Keep the check for Redis availability (`@definition_store.check_connection`).
*   [ ] Refactor `GET /agents`:
    *   Replace `@redis.smembers` and pipelined `HMGET` with `@definition_store.list_definitions()`.
    *   Adjust data mapping to match the format returned by the store.
    *   Check store availability (`if @definition_store`).
*   [ ] Refactor `POST /agents`:
    *   Replace `@redis.sismember` with `@definition_store.definition_exists?`.
    *   Replace `@redis.multi` block with `@definition_store.save_definition(...)`.
    *   Pass validated data (name, desc, tools array, model, fallback, mcp JSON) to the store method.
    *   Check store availability.
*   [ ] Refactor `DELETE /agents/:name`:
    *   Replace `@redis.exists?` check (if needed, or rely on store method's return).
    *   Replace `@redis.multi` block with `@definition_store.delete_definition(name)`.
    *   Check store availability.
*   [ ] Refactor `GET /agents/:name`:
    *   Replace `@redis.hmget` with `@definition_store.get_definition(name)`.
    *   Adjust data access based on the hash returned by the store.
    *   Handle `nil` return from store (agent not found).
    *   Check store availability.
*   [ ] Refactor `GET /agents/:name/edit/:field`:
    *   Replace `@redis.exists?` check (or rely on store).
    *   Replace `@redis.hmget` with `@definition_store.get_definition(name)`.
    *   Adjust data access.
    *   Check store availability.
*   [ ] Refactor `GET /agents/:name/display/*`:
    *   Replace `@redis.hmget` with `@definition_store.get_definition(name)`.
    *   Adjust data access.
    *   Check store availability.
*   [ ] Refactor `PUT /agents/:name/update/:field`:
    *   Replace `@redis.exists?` check (or rely on store).
    *   Replace `@redis.hset` with `@definition_store.update_definition(name, { redis_field_to_update => new_value_to_save })`.
    *   Handle potential validation errors returned by the store method if implemented.
    *   Check store availability.
*   [ ] Refactor `_start_agent` helper method:
    *   Replace `@redis.hmget` with `@definition_store.get_definition(name)`.
    *   Adjust data access.
    *   Check store availability.
*   [ ] Refactor `GET /api/agents`:
    *   Replace `@redis.smembers` and pipelined `HMGET` with `@definition_store.list_definitions()`.
    *   Adjust data mapping.
    *   Check store availability.
*   [ ] Refactor `GET /healthz`:
    *   Replace `@redis.ping` with `@definition_store.check_connection()`.
    *   Adjust error handling based on store method's return/exceptions.
    *   Check store availability.
*   [ ] Refactor `GET /agents/:name/generate_example_task`:
    *   Replace `@redis.hmget` with `@definition_store.get_definition(name)`.
    *   Adjust data access.
    *   Handle `nil` return.
    *   Check store availability.

### Phase 3: Testing and Documentation

*   [ ] Run existing web app tests (if any) and update/add new ones to cover refactored routes.
*   [ ] Perform thorough manual testing of all agent definition CRUD operations and related features in the web UI.
*   [ ] Update `docs/web-app.md` if any user-facing aspects or setup instructions changed (e.g., if Redis configuration changes).
*   [ ] Mark this plan as complete. 
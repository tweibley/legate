# MCP Schema Conversion Details

This document details the automatic conversion processes between the different schema formats used by Legate, the Model Context Protocol (MCP), and the `fast-mcp` gem. Understanding this is helpful when defining tools or troubleshooting integration issues.

## Formats

*   **Legate Parameters:** Defined within a `Legate::Tool` subclass using the `parameter` DSL (with `tool_description` for the description). Internally these are stored as a Ruby hash like:
    ```ruby
    { 
      param_name: { 
        type: :symbol, # :string, :integer, :numeric, :boolean, :array, :hash 
        required: boolean, 
        description: string 
      }, 
      # ... 
    }
    ```
*   **MCP JSON Schema:** Standard JSON Schema objects used in MCP `tools/list` (`inputSchema`) and `resources/list` (`schema`).
    ```json
    { 
      "type": "object", 
      "properties": { 
        "param_name": { "type": "string", "description": "..." }
      },
      "required": ["param_name"]
    }
    ```
*   **Dry::Schema:** Used by `fast-mcp` within the `arguments` block to define and validate tool parameters.
    ```ruby
    arguments do
      required(:param_name).filled(:string).description("...")
    end
    ```

## Conversion Flows

### 1. MCP JSON Schema -> Legate Params

*   **Where:** Done by `Legate::Mcp::ToolWrapper.from_mcp_schema` using `Legate::Mcp::Util::SchemaConverter.json_to_legate`.
*   **Use Case:** When an Legate Agent connects to an external MCP server and discovers its tools (Client Mode).
*   **Mapping (V1):** Basic types (`string`, `integer`, `number`, `boolean`) are mapped to corresponding Legate types (`:string`, `:integer`, `:numeric`, `:boolean`). `required` status and `description` are preserved.
*   **Limitations (V1):** Complex types (`object`, `array`), constraints (`minLength`, `enum`, `format` etc.) are **ignored** during conversion. Only the basic type, requirement, and description are used.

### 2. Legate Params -> Dry::Schema

*   **Where:** Done by `Legate::Mcp::Server::LegateToolAdapter.wrap` using `Legate::Mcp::Util::SchemaConverter.legate_to_dry_schema`.
*   **Use Case:** When exposing an `Legate::Tool` via `fast-mcp` (Server Mode).
*   **Mapping (V1):** Basic Legate types (`:string`, `:integer`, `:numeric`, `:boolean`) are mapped to appropriate `Dry::Schema` calls (`filled(:string)`, `filled(:integer)`, `filled(Dry::Types['coercible.float'])`, `filled(:bool)`). `:required` status maps to `required()` or `optional()`.
*   **Limitations (V1):** Legate types `:array`, `:hash`, `:object` receive basic mappings (`value(:array)`, `value(:hash)`) **without** nested schema validation. Parameter descriptions from Legate metadata are **not** added to the Dry::Schema block itself (they are set separately on the `fast-mcp` tool using `description` DSL by the adapter).

### 3. Legate Params -> JSON for MCP Call (Client)

*   **Where:** Inside `Legate::Mcp::ToolWrapper#perform_execution`.
*   **Use Case:** When an Legate Agent executes an external MCP tool.
*   **Mapping (V1):** Simple conversion of the Legate params hash (symbol keys) to a JSON hash (string keys). Assumes a flat structure.

## Key Takeaway

For V1, schema conversion primarily supports basic data types and required fields. Complex nested structures or validation rules defined in one system may not be fully enforced or represented when crossing the Legate <-> MCP boundary.

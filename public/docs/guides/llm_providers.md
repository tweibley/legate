# LLM Providers

Legate's planner talks to a Large Language Model through a small, pluggable adapter interface (`Legate::LLM::Adapter`). **Gemini is the default**, but you can point Legate at any provider — a hosted API, a local model, or your own implementation — without changing your agents.

## The adapter interface

An adapter is any object that responds to three methods:

```ruby
class MyAdapter < Legate::LLM::Adapter
  # Whether the adapter can make calls (e.g. an API key is present).
  def available?; true; end

  # The resolved model id, or nil if unavailable.
  def model_name; 'my-model'; end

  # Generate a completion for a single prompt.
  # @param prompt [String]
  # @param json [Boolean] request raw-JSON output where the provider supports it
  # @return [String, nil] the model's text output (nil if unavailable)
  def generate(prompt, json: false)
    # ... call your provider, return the text ...
  end
end
```

The planner calls `generate(prompt, json: true)` and parses a JSON plan out of the returned text, so any provider that can return text (ideally JSON-constrained) works. An adapter can additionally implement `supports_structured_output?` + accept a `schema:` to **guarantee** valid plan JSON via the provider's native structured output — `Legate::LLM::Gemini` does this (Gemini `responseSchema`), so plans on Gemini are schema-constrained rather than parsed out of prose.

## Built-in adapters

### Gemini (default)

Used automatically when no other provider is configured. Requires `GOOGLE_API_KEY` (or `GEMINI_API_KEY`).

```ruby
Legate::LLM::Gemini.new(model: 'gemini-3.5-flash', api_key: ENV['GOOGLE_API_KEY'])
```

### Ollama (local)

Talks to a local [Ollama](https://ollama.com) server over HTTP — **no API key, no cost, fully local**. Configure the host with the `:host` option or the `OLLAMA_HOST` env var (default `http://localhost:11434`).

```ruby
Legate::LLM::Ollama.new(model: 'llama3')               # http://localhost:11434
Legate::LLM::Ollama.new(model: 'qwen2.5', host: 'http://gpu-box:11434', read_timeout: 180)
```

It requests JSON-constrained output (Ollama's `"format": "json"`) when the planner asks for a plan.

## Selecting a provider for every agent

Set a factory once at boot. It receives `model:`, `api_key:`, and `logger:` keyword arguments and returns an adapter:

```ruby
# Use a local Ollama model everywhere instead of Gemini
Legate::LLM.default_adapter_factory = lambda do |model:, **|
  Legate::LLM::Ollama.new(model: model)
end
```

When unset (the default), Legate uses the Gemini adapter. The per-agent `model_name` is passed through to your factory as `model:`, so you can still vary the model per agent.

## Overriding for a single planner

If you construct a planner directly, you can inject an adapter for just that instance (this takes precedence over the global factory):

```ruby
adapter = Legate::LLM::Ollama.new(model: 'llama3')
planner = Legate::Planner.new(agent: my_agent, llm_adapter: adapter)
```

> Most users won't construct planners by hand — agents build their own. The `default_adapter_factory` above is the usual way to choose a provider.

## Writing a custom adapter

To support a provider Legate doesn't ship (OpenAI, Anthropic, a gateway, a mock for tests), implement the three interface methods and wire it through the factory:

```ruby
class OpenAIAdapter < Legate::LLM::Adapter
  def initialize(model:, api_key: ENV['OPENAI_API_KEY'], logger: nil, **)
    @model = model
    @api_key = api_key
    @logger = logger || Legate.logger
  end

  def available?
    !@api_key.to_s.empty?
  end

  def model_name
    available? ? @model : nil
  end

  def generate(prompt, json: false)
    # POST to your provider, return the assistant's text.
    # Pass a JSON-mode / response-format flag when json is true.
  end
end

Legate::LLM.default_adapter_factory = lambda do |model:, **|
  OpenAIAdapter.new(model: model)
end
```

That's the whole contract — `available?`, `model_name`, `generate(prompt, json:)`.

## Optional: native function calling

[Agentic (`:react`) agents](agentic_agents) pick their next action one step at a
time. By default the planner does this by prompting for a JSON action and parsing
it — works with any adapter. An adapter can opt into the provider's **native
tool-calling API** instead (more reliable: the tool name and arguments come back
typed, not parsed out of prose) by implementing two more methods:

```ruby
def supports_function_calling?
  true
end

# @param tools [Array<Hash>] each { name:, description:, parameters: <JSON Schema> }
# @return [Hash] { kind: :tool, name:, arguments:, thought: } or { kind: :final, text:, thought: }
def generate_with_tools(prompt, tools:)
  # Call your provider's function-calling endpoint with the tool schemas,
  # then return the structured choice in the neutral shape above.
end
```

`Legate::LLM::Gemini` implements both, so agentic agents on Gemini use native
function calling automatically. Adapters that don't (Ollama, the default custom
adapter) inherit `supports_function_calling? => false` and stay on the JSON path —
no action needed. This affects only the agentic next-action decision; the
multi-step planner still uses `generate`.

## See also

- [Agentic Agents](agentic_agents) — the ReAct loop these adapters reason through.
- [Legate Planner](../core_concepts/legate_planner) — how the planner turns a model response into an executable plan.

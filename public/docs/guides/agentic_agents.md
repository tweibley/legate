# Agentic Agents (ReAct loop)

By default a Legate LLM agent **plans once, then executes**: the planner asks the
model for a complete list of tool steps up front, and the agent runs them in
order. That is fast and predictable, but it can't react — if step 2 returns
something unexpected, step 3 still runs the original plan.

The **agentic** strategy replaces the single up-front plan with an
observe → think → act loop (the "ReAct" pattern): the agent takes **one** action,
observes the result, then decides the next action with that result in hand. It
keeps going until the model produces a final answer.

## When to use it

| Use **`:plan`** (default) when… | Use **`:react`** when… |
|---|---|
| The steps are known ahead of time | Later steps depend on earlier results |
| You want the fewest LLM round-trips | The task is exploratory or multi-step |
| The task is a single tool call | A tool may fail and the agent should adapt |

`:react` makes more LLM calls (one per step) in exchange for the ability to
course-correct. For a one-shot tool call, `:plan` is cheaper and just as good.

## Enabling it

### In the DSL

```ruby
definition = Legate::AgentDefinition.new
definition.define do |a|
  a.name :researcher
  a.description 'Looks things up step by step.'
  a.instruction 'Answer the user by searching and reading, one step at a time.'
  a.use_tool :search
  a.use_tool :fetch
  a.planning_strategy :react   # opt in; omit (or :plan) for the default
end
```

`planning_strategy` accepts `:plan` (default) or `:react`. It applies to `:llm`
agents; it has no effect on workflow agents (`:sequential`, `:parallel`, `:loop`).

### In the web UI

On an agent's detail page, open **Edit Type**. Alongside *Agent Type* there is a
**Planning Strategy** dropdown — choose *ReAct (agentic loop)* and save. The same
control is available when creating a new agent. The agent's type panel shows a
**ReAct** tag when the loop is active.

## How the loop works

Each turn, the planner sends the model the user's request plus every observation
so far, and asks for the single next action as a JSON object:

```jsonc
// call a tool
{"thought": "I should search first", "action": "tool",
 "tool_name": "search", "tool_input": {"q": "ruby agents"}}

// finish
{"thought": "I have enough to answer", "action": "final",
 "answer": "Here's what I found…"}
```

1. **Think** — `Planner#reason_next_action` asks the adapter for the next action
   and turns the answer into a `Legate::Agentic::Decision`. How it asks depends on
   the provider (see [Native function calling](#native-function-calling) below):
   either a native tool call or the JSON object above parsed out of the response.
2. **Act** — if the decision is a tool call, the agent runs it through the same
   executor, event logging, and state-delta machinery as the default strategy.
   Tool requests and results are appended to the session exactly as usual.
3. **Observe** — the (sanitized) result is appended to the running list of
   observations and fed back into the next turn's prompt.

The loop ends when the model returns `"action": "final"`; the answer becomes the
agent's result event, identical in shape to a `:plan` run.

### Tool errors don't abort the loop

If a tool returns an error — or raises — the failure is captured as an
**observation** rather than ending the turn. The model sees the error on the next
step and can retry with different input, try another tool, or give up gracefully.
This is the headline advantage over plan-then-execute, which stops at the first
failed step.

### Safeguards

- **Iteration cap.** The loop runs at most `DEFAULT_MAX_ITERATIONS` (8) steps, so
  a confused agent can't loop forever. If it hasn't finished by then it makes one
  best-effort pass — asking the model to answer from the observations gathered —
  and returns that as the result. If even that can't be produced (e.g. no LLM
  available), it returns an error result noting the cap.
- **Loop-breaker.** If the model repeats the *exact same* action and gets the
  *exact same* result, re-running won't help — the loop stops early (again with a
  best-effort summary) instead of spinning through the rest of the budget.
- **Observation truncation.** Tool outputs are trimmed before being fed back so a
  big result doesn't blow up the next turn's prompt: deeply-nested structures
  become `[Complex Result Structure]`, and long strings are cut to ~2,000
  characters with a `[truncated N chars]` marker. Simple scalar results pass
  through intact.
- **Tool-name validation.** A tool name from the model is validated against the
  agent's registry (and its delegation targets) before it is interned or run —
  the same guard the multi-step planner uses — so untrusted model output can't
  invoke arbitrary tools.

## Native function calling

How the loop *asks* for the next action depends on the LLM adapter:

- **Adapters with native function calling** (Gemini, the default) receive the
  tools as structured function declarations and return a real function call. No
  JSON is parsed out of prose — the tool name and arguments come back typed,
  which is markedly more reliable. This happens automatically; you don't
  configure anything.
- **Adapters without it** (Ollama, custom adapters) fall back to the JSON-object
  prompt shown above. Same `Decision`, same loop — only the mechanism differs.

An adapter advertises support via `supports_function_calling?` and implements
`generate_with_tools(prompt, tools:)` (see
[LLM Providers](llm_providers)). The validation, safeguards, and everything
downstream are identical on both paths; the agent's registered tools and its
delegation targets are offered either way.

> Scope: native function calling powers the **agentic** next-action decision. The
> default plan-then-execute planner still uses JSON-mode output.

## What stays the same

Switching strategies does **not** change anything else about your agent. Tools,
sessions, state deltas, callbacks (`before_tool`, `after_tool`, `before_model`,
…), MCP integration, and the final result-event shape all behave identically.
`:react` is purely a change in *how the next action is chosen*.

## Related

- [LLM Providers](llm_providers) — the adapter the loop reasons through.
- [Legate Planner](../core_concepts/legate_planner) — the default plan-then-execute flow.

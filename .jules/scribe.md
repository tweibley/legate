## 2025-02-23 - SessionService Interface Documentation Gap

**Gap:** The `ADK::SessionService::Base#append_event` method was completely undocumented, despite being a core method of the session service interface that raises `NotImplementedError`. Extenders would have to guess its contract by looking at subclasses (`Redis` or `InMemory`).

**Learning:** Interfaces (even "base classes" in Ruby) need thorough documentation because they serve as the contract for future implementations. When a method raises `NotImplementedError`, it's *more* important to document it than a concrete method, because the code itself doesn't show "how" it works, only that it "must" work.

**Action:** When surveying abstract base classes or interfaces, specifically check methods that raise `NotImplementedError` for missing YARD documentation.

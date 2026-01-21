## 2026-01-21 - [Extract PlanExecutor from Agent]

**Issue:** `ADK::Agent` was a God Class handling configuration, tool management, and execution logic (plan & step execution). This violated the Single Responsibility Principle.
**Learning:** Extracting execution logic into `ADK::PlanExecutor` improves cohesion and reduces the size/complexity of `ADK::Agent`. However, dependencies like callbacks and private methods (auth config) required careful handling (passing agent instance and using `send` for private access) to avoid breaking encapsulation or requiring widespread API changes.
**Action:** Created `ADK::PlanExecutor` and delegated execution from `ADK::Agent`. Maintained backward compatibility by keeping `execute_plan` as a facade in `ADK::Agent`.

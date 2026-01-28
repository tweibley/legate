## 2025-02-18 - Registry Pattern Unification

**Issue:** `GlobalToolManager` and `ToolRegistry` had duplicated logic for managing tool collections. `GlobalToolManager` acted as a "God Class" implementation of a registry, while `ToolRegistry` was the instance-based version. This led to code duplication and inconsistency.
**Learning:** The "Global" manager is just a singleton instance of the registry. By unifying them, we enforce consistency. However, `GlobalToolManager` had implicit API contracts (formatting of `list_all_tools`) that had to be preserved in `ToolRegistry` to avoid breaking consumers.
**Action:** Refactored `GlobalToolManager` to wrap a static `ToolRegistry` instance. Enhanced `ToolRegistry` to support class-based registration (`register_class`) and robust listing formatting.

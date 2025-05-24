# PRD: Authentication Scheme Cleanup and Consistency Fixes

## 1. Product overview

### 1.1 Document title and version

-   PRD: Authentication Scheme Cleanup and Consistency Fixes
-   Version: 1.0

### 1.2 Product summary

The ADK-Ruby authentication system has several critical inconsistencies and architectural issues that were introduced during implementation. These include orphaned authentication schemes that aren't properly loaded, duplicate implementations with different interfaces, inconsistent naming conventions, and mismatches between scheme types and their actual availability. This cleanup project will resolve these issues to create a cohesive, well-architected authentication system that users can rely on.

The work involves consolidating duplicate implementations, fixing loader inconsistencies, standardizing naming conventions, ensuring comprehensive test coverage, and updating all documentation and examples to reflect the corrected architecture.

## 2. Goals

### 2.1 Business goals

-   Eliminate confusion and inconsistencies in the authentication API that could lead to developer frustration
-   Provide a reliable, well-tested authentication system that supports all documented schemes
-   Reduce maintenance burden by eliminating duplicate implementations
-   Ensure consistent behavior across all authentication schemes

### 2.2 User goals

-   Use any documented authentication scheme without encountering missing classes or inconsistent behavior
-   Have clear, working examples for all authentication types
-   Experience consistent naming and interfaces across all authentication schemes
-   Rely on comprehensive test coverage for authentication functionality

### 2.3 Non-goals

-   Adding new authentication schemes or functionality (this is purely a cleanup effort)
-   Changing the fundamental architecture of the authentication system
-   Breaking existing working code (all fixes should be backward compatible where possible)

## 3. User personas

### 3.1 Key user types

-   Ruby developers integrating ADK authentication into their applications
-   DevOps engineers setting up authentication for deployed applications
-   Library maintainers working on the ADK codebase

### 3.2 Basic persona details

-   **Application Developer**: Needs reliable, documented authentication schemes that work as expected
-   **DevOps Engineer**: Requires consistent configuration patterns across different authentication types
-   **Library Maintainer**: Needs clean, well-tested code without duplicated or orphaned implementations

### 3.3 Role-based access

-   **End Users**: Access to working authentication schemes through documented APIs
-   **Maintainers**: Access to clean, well-structured internal authentication code

## 4. Functional requirements

-   **Scheme Loading Consistency** (Priority: High)
    -   All authentication schemes referenced in examples, tests, and documentation must be properly loaded by the main schemes loader
    -   Remove or properly integrate orphaned scheme implementations
    -   Ensure credential types match available schemes

-   **Naming Convention Standardization** (Priority: High)
    -   Standardize class names and aliases across all authentication schemes
    -   Fix inconsistent casing in class references (HTTPBearer vs HttpBearer)
    -   Ensure consistent scheme type symbols

-   **Duplicate Implementation Resolution** (Priority: High)
    -   Choose canonical implementations for Bearer token and OIDC authentication
    -   Remove or properly differentiate duplicate implementations
    -   Ensure consistent interfaces across similar schemes

-   **Test Coverage Completeness** (Priority: High)
    -   Add comprehensive tests for all schemes that are meant to be used
    -   Remove tests for schemes that are being deprecated
    -   Ensure all scheme loading paths are tested

-   **Documentation Synchronization** (Priority: Medium)
    -   Update all documentation to reference only the canonical implementations
    -   Fix examples to use consistent, working scheme references
    -   Update API documentation to match actual available classes

## 5. User experience

### 5.1 Entry points & first-time user flow

-   Developers discover authentication schemes through documentation and examples
-   They expect that any scheme mentioned in documentation can be successfully instantiated and used

### 5.2 Core experience

-   **Scheme Discovery**: Developers can find authentication schemes through consistent documentation
    -   All documented schemes are actually available and functional
-   **Scheme Instantiation**: Creating scheme instances works reliably
    -   No missing class errors for documented schemes
-   **Credential Matching**: Credential types properly match available schemes
    -   No mismatches between credential auth_type and available schemes

### 5.3 Advanced features & edge cases

-   Multiple schemes of the same type (e.g., different OAuth2 providers) work consistently
-   Scheme inheritance and specialization (e.g., GoogleServiceAccount) works properly
-   Environment-based configuration works across all scheme types

### 5.4 UI/UX highlights

-   Clear error messages when schemes are misconfigured
-   Consistent method signatures across similar schemes
-   Logical naming that matches industry standards

## 6. Narrative

A developer working with ADK authentication will discover available schemes through clear documentation, successfully instantiate any documented scheme without encountering missing class errors, and experience consistent behavior and naming conventions across all authentication types. They can confidently choose the appropriate scheme for their use case knowing that it's fully supported, tested, and documented.

## 7. Success metrics

### 7.1 User-centric metrics

-   Zero instances of "class not found" errors for documented schemes
-   Consistent method signatures across scheme implementations
-   All examples and documentation work without modification

### 7.2 Business metrics

-   Reduced support requests related to authentication setup issues
-   Faster developer onboarding due to consistent authentication patterns

### 7.3 Technical metrics

-   100% test coverage for all public authentication scheme classes
-   Zero orphaned or unused authentication code
-   Consistent loading time across all scheme types

## 8. Technical considerations

### 8.1 Integration points

-   Main authentication module loading (`lib/adk/auth.rb`)
-   Scheme factory (`lib/adk/auth/schemes.rb`)
-   Authentication manager registration
-   Tool integration and middleware factory
-   Web UI authentication flows

### 8.2 Data storage & privacy

-   No changes to credential storage or encryption (cleanup only)
-   Maintain existing security properties
-   Preserve session management capabilities

### 8.3 Scalability & performance

-   No performance impact expected (primarily organizational changes)
-   May improve loading time by removing unused code
-   Maintain existing scalability characteristics

### 8.4 Potential challenges

-   Determining which duplicate implementation to keep
-   Ensuring backward compatibility while fixing inconsistencies
-   Updating all references across a large codebase
-   Risk of breaking existing user code during cleanup

## 9. Milestones & sequencing

### 9.1 Project estimate

-   Medium: 3-5 days

### 9.2 Team size & composition

-   Small Team: 1 developer

### 9.3 Suggested phases

-   **Phase 1**: Analysis and Decision Making (0.5 day)
    -   Key deliverables: Decisions on which implementations to keep, deprecation plan
-   **Phase 2**: Core Scheme Cleanup (2 days)
    -   Key deliverables: Fixed scheme loading, resolved duplications, updated core classes
-   **Phase 3**: Documentation and Examples Update (1.5 days)
    -   Key deliverables: Updated documentation, fixed examples, consistent references
-   **Phase 4**: Testing and Validation (1 day)
    -   Key deliverables: Complete test coverage, validated examples, integration testing

## 10. User stories

### 10.1 Fix Orphaned OIDC Scheme Integration

-   **ID**: US-001
-   **Description**: As a developer, I want to use the OIDC authentication scheme that's referenced in examples and documentation so that I can implement OpenID Connect authentication without encountering missing class errors.
-   **Acceptance Criteria**:
    -   The OIDC scheme referenced in examples (`ADK::Auth::Schemes::OIDC`) is properly loaded by the main schemes loader
    -   Examples using OIDC authentication run without modification
    -   Tests exist and pass for the OIDC scheme implementation

### 10.2 Resolve Bearer Token Implementation Duplication

-   **ID**: US-002
-   **Description**: As a developer, I want a single, consistent Bearer token authentication implementation so that I don't have to choose between multiple confusing options.
-   **Acceptance Criteria**:
    -   Only one Bearer token scheme implementation exists and is documented
    -   All references to Bearer authentication use the same class name consistently
    -   The Bearer token interface is consistent with other authentication schemes

### 10.3 Fix Service Account Scheme Loading

-   **ID**: US-003
-   **Description**: As a developer, I want to use service account authentication schemes that are documented and tested so that I can implement service account flows reliably.
-   **Acceptance Criteria**:
    -   Both `ServiceAccount` and `GoogleServiceAccount` schemes are properly loaded by the main schemes loader
    -   Examples using service account authentication work without modification
    -   Credential types properly support service account authentication

### 10.4 Standardize HTTPBearer Naming

-   **ID**: US-004
-   **Description**: As a developer, I want consistent naming for the HTTP Bearer authentication scheme so that I can use it reliably across different parts of the codebase.
-   **Acceptance Criteria**:
    -   All references use either `HTTPBearer` or `HttpBearer` consistently (not both)
    -   Documentation uses the canonical class name
    -   Tests and examples use the canonical class name

### 10.5 Ensure Credential Type Consistency

-   **ID**: US-005
-   **Description**: As a developer, I want credential types to match the actually available authentication schemes so that I don't encounter configuration errors.
-   **Acceptance Criteria**:
    -   All credential auth_types have corresponding loaded schemes
    -   No credential types reference unavailable or orphaned schemes
    -   Error messages clearly indicate available credential types

### 10.6 Complete Test Coverage for All Schemes

-   **ID**: US-006
-   **Description**: As a library maintainer, I want comprehensive test coverage for all authentication schemes so that I can confidently make changes without breaking functionality.
-   **Acceptance Criteria**:
    -   Tests exist for all schemes that are loaded by the main schemes loader
    -   No tests exist for orphaned or removed schemes
    -   All test files follow consistent naming and structure patterns

### 10.7 Update Documentation and Examples

-   **ID**: US-007
-   **Description**: As a developer, I want documentation and examples that reference only the canonical, working authentication schemes so that I can successfully implement authentication without trial and error.
-   **Acceptance Criteria**:
    -   All documentation references use canonical class names
    -   Examples run successfully without modification
    -   API documentation matches actual available classes and methods

### 10.8 Validate Authentication Manager Integration

-   **ID**: US-008
-   **Description**: As a developer, I want the authentication manager to properly register and provide access to all supported schemes so that scheme discovery and instantiation works reliably.
-   **Acceptance Criteria**:
    -   Authentication manager registers all canonical schemes
    -   Scheme factory can create instances of all documented schemes
    -   No references to orphaned or duplicate schemes in manager code 
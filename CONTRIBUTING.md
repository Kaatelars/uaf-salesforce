# Contributing to the Unified Automation Framework (UAF)

Thanks for your interest in improving UAF! This guide explains how to propose changes, run the
test suite locally, and write commits that fit the project history.

## Code of Conduct

Be respectful and constructive. Assume good intent, focus feedback on the code, and keep
discussions on topic.

## Ways to Contribute

- **Report a bug.** Open an issue with the steps to reproduce it, the expected and actual
  behavior, your API version and, if possible, a minimal Apex/Flow snippet.
- **Propose a feature.** Open an issue describing the use case before writing code, so we
  can agree on the design (especially for public API changes).
- **Improve docs.** README fixes, examples and ApexDoc improvements are always welcome.
- **Submit code.** Follow the workflow below.

## Development Workflow

1. **Fork** the repository and clone your fork.
2. **Create a branch** from `main` using a descriptive name:
   `feat/cmdt-handler-registry`, `fix/flowguard-null-record`, `docs/readme-examples`.
3. **Authorize an org** for development. Use a Developer Edition org, a sandbox or a scratch org:

   ```bash
   # Existing org
   sf org login web --alias uaf-dev

   # Or a scratch org (requires a Dev Hub)
   sf org create scratch --definition-file config/project-scratch-def.json \
     --alias uaf-dev --duration-days 7 --target-dev-hub <your-devhub-alias>
   ```

4. **Make your changes** following the [coding conventions](#coding-conventions).
5. **Deploy and test** ([see below](#running-tests-locally)). Every change must deploy cleanly
   and keep the full suite green.
6. **Run static analysis** ([see below](#static-analysis-salesforce-code-analyzer)). No violations
   of severity 1–3 are allowed.
7. **Commit** using [Conventional Commits](#commit-conventions).
8. **Open a Pull Request** against `main` and fill in the [PR checklist](#pull-request-checklist).

## Running Tests Locally

Always pass `--target-org` explicitly so you never deploy to the wrong org by accident.

> **Run the tests as a regular admin, never as a user who has the `UAF_Bypass_Automations`
> Permission Set.** For that user every automation is bypassed, so the automation tests fail.

```bash
# Deploy the framework and the reference implementation
sf project deploy start --target-org uaf-dev

# Run the whole suite with coverage
sf apex run test --code-coverage --result-format human --wait 15 --target-org uaf-dev

# Run only the framework tests
sf apex run test --class-names UAF_Core_Test --class-names UAF_BypassManager_Test --class-names UAF_Flow_Test \
  --code-coverage --result-format human --wait 10 --target-org uaf-dev

# Run only the end-to-end reference tests
sf apex run test --class-names Account_UAF_Integration_Test \
  --code-coverage --result-format human --wait 10 --target-org uaf-dev
```

| Test class | Package dir | Scope |
|---|---|---|
| `UAF_Core_Test` | `force-app` | Factory, dispatcher base, re-entrancy, trigger parameters |
| `UAF_BypassManager_Test` | `force-app` | In-memory bypasses and the user-level `UAF_Bypass_All` Custom Permission (real Permission Set assignment) |
| `UAF_Flow_Test` | `force-app` | `UAF_FlowGuard`, `UAF_FlowInvoker`, `UAF_FlowExecutionResult` (uses `UAF_Test_Echo_Flow`) |
| `Account_UAF_Integration_Test` | `reference-app` | End-to-end DML on Account through the real trigger and the guarded Flow, including FLS and data-load (bypass) users |

The full suite runs in well under a minute. If a change makes it noticeably slower, look for
users being created per test method (see [Tests](#tests)).

**Coverage requirements**

- At least **85%** per class. The current suite is at **100%**; please keep it there.
- Framework tests must **not** depend on org contents. For example, don't assume an object
  has (or lacks) a dispatcher. Use the `@TestVisible` seams instead, such as
  `UAF_TriggerFactory.DISPATCHER_OVERRIDES` and `instantiateDispatcher`.
- Cover positive, negative, bulk (200+ records), re-entrancy and bypass scenarios.

## Static Analysis (Salesforce Code Analyzer)

Every PR must pass [Salesforce Code Analyzer](https://developer.salesforce.com/docs/platform/salesforce-code-analyzer/overview)
(v5, `sf code-analyzer`) with **no violations of severity 1, 2 or 3** in either package directory:

```bash
sf plugins install code-analyzer        # once

sf code-analyzer run --workspace . --target force-app \
  --rule-selector pmd --severity-threshold 3 --view table
sf code-analyzer run --workspace . --target reference-app \
  --rule-selector pmd --severity-threshold 3 --view table
```

The command exits with a non-zero code if a violation at or above the threshold is found.

- **Fix the code first.** For example, use a builder instead of long Boolean parameter lists,
  `WITH SYSTEM_MODE` / `WITH USER_MODE` to make the access mode explicit, and
  `Security.stripInaccessible` before DML.
- **Suppressions are a last resort.** Use `@SuppressWarnings('PMD.<Rule>')` on the narrowest
  scope possible, and only with a justification in the ApexDoc. The only suppression today is
  `PMD.EmptyStatementBlock` on `UAF_TriggerDispatcherBase`, whose empty virtual methods are
  intentional template-method hooks.
- Severity 4–5 findings (e.g. `ApexDoc`) are not blocking, but fixing them is welcome.

## Coding Conventions

### Package boundaries

- `force-app/` contains **only** the framework (`UAF_*`) and its test fixtures. Nothing
  specific to a business object (triggers, dispatchers, handlers, fields) goes here.
- `reference-app/` contains the example Account implementation and its integration tests.

### Apex

- **`UAF_` prefix** for every framework class; the `_Test` suffix for test classes.
- **Strict bulkification**: work on collections and support 200+ records per batch.
- **No SOQL or DML inside loops.** Query once, map by Id or key, and issue one DML per operation.
- Keep the framework's governor-limit footprint at **zero SOQL/DML** on the trigger path. Any
  new query must be opt-in and cached per transaction (see `UAF_FlowInvoker`).
- **Sharing modifiers are mandatory on every class** (interfaces excepted):
  - `force-app` (framework): **`inherited sharing`**, so framework code always runs in the
    sharing context of its caller and never widens it.
  - `reference-app` (business code): **`with sharing`**.
  - `without sharing` requires a written justification in the ApexDoc and maintainer approval.
- **Make the data access mode explicit.**
  - Use `WITH USER_MODE` / `AccessLevel.USER_MODE` for business data.
  - Use `WITH SYSTEM_MODE` only for platform metadata (e.g. `FlowDefinitionView`), with a comment.
  - Before DML on user-facing records, call `Security.stripInaccessible` and run the DML in user mode.
- **Enum constants are `UPPER_SNAKE_CASE`** (e.g. `TriggerEvent.AFTER_UPDATE`).
- **ApexDoc** on every public class and method (`@description`, `@param`, `@return`,
  `@throws`). Comments explain *why*, not *what*.
- No hardcoded Ids, profile names or org-specific values.
- Remember that Apex is **case-insensitive**: a property named `triggerEvent` shadows the
  enum type `TriggerEvent` inside the same class. Use fully qualified names
  (`UAF_TriggerParameters.TriggerEvent.AFTER_UPDATE`).

### Tests

- Use the modern **`Assert`** class (`Assert.areEqual`, `Assert.isTrue`, `Assert.isNull`,
  `Assert.fail`, `Assert.isInstanceOfType`, ...) and always include a descriptive message.
  Don't use the legacy `System.assert*` methods.
- Use `Test.startTest()` / `Test.stopTest()` around the code under test.
- **Create test users once per class in `@TestSetup`** with `UAF_TestDataFactory.createUser(tag, permissionSets)`
  and fetch them with `UAF_TestDataFactory.getUser(tag)`. Inserting users and Permission Set
  assignments in every test method makes parallel test runs wait on Setup-object locks, which
  once pushed the suite from seconds to about 8 minutes.
- Prefer the simulated user-level bypass (`UAF_BypassManager.bypassAllOverride = true`) unless
  the test is specifically about the real Permission Set assignment.
- **No hardcoded Ids.** Use `UAF_TestDataFactory.fakeId(SObjectType, index)`.
- Simulate trigger contexts with `UAF_TriggerParameters.Builder` instead of DML when you unit
  test dispatchers and handlers.

### Flows

- API version **68.0**.
- Record-Triggered Flows that participate in UAF governance must call **UAF Flow Guard** as
  their first element, passing their own API name and `{!$Record.Id}`.

## Commit Conventions

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<optional scope>): <short imperative summary>

<optional body: what changed and why, wrapped at ~72 chars>
```

| Type | Use for |
|---|---|
| `feat` | A new feature or public API |
| `fix` | A bug fix |
| `docs` | Documentation only |
| `test` | Adding or fixing tests only |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | Performance or governor-limit improvement |
| `chore` | Tooling, config, metadata housekeeping |

Suggested scopes: `core`, `flow`, `bypass`, `reference`, `docs`.

Examples:

```
feat(flow): add UAF_BypassAction invocable to toggle bypasses from Flow
fix(core): release re-entrancy flag when handler throws
docs: document FlowGuard limitations for before-save flows
```

Mark breaking changes with `!` after the type/scope (for example `feat(core)!: ...`) and
describe the migration in the body.

## Pull Request Checklist

- [ ] The branch is up to date with `main`.
- [ ] `sf project deploy start` succeeds.
- [ ] The full test suite passes and coverage is ≥ 85% per class (target: 100%).
- [ ] `sf code-analyzer run ... --severity-threshold 3` reports no violations for `force-app` and `reference-app`.
- [ ] Every new class declares its sharing modifier (`inherited sharing` in `force-app`, `with sharing` in `reference-app`).
- [ ] New or changed behavior is covered by tests (bulk, bypass and re-entrancy where relevant).
- [ ] ApexDoc and the README are updated for any public API change.
- [ ] Commits follow Conventional Commits.

## License

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE).

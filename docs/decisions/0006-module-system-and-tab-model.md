# 0006 — Module system, tab model split and fakes target

- Status: Accepted
- Date: 2026-10-17
- WP: P1-04

## Context

P1-04 builds the extensibility backbone of DESIGN §4.10: modules contribute through registries
to an `@MainActor` app state. Several things DESIGN v1 left open turned out to matter:

- `AppState` lives in Core and needs tab identity, title, badges and aliases (tab bar, voice
  "go to the api", attention). But a tab's content is a `View`, and Core can't import
  `VoCoderUI`.
- DESIGN §4.1 puts the fakes in `VoCoderTestSupport`, which also holds the contract suites and
  therefore imports Swift Testing. `vocoder --demo` runs on the fakes, so the executable would
  link the testing library.
- Not-yet-built seams (`AgentBackend`, `TaskTracker`, …) need to exist now so registries,
  fakes and contract suites have a shape. Their members belong to later WPs.
- `LanguageModel` (ADR 0003) has to stay vendor-neutral, but the intent schema is generated per
  context from the available commands, so it can't be a static `@Generable` type in Core.

## Decision

- **Modules**: `VoCoderModule` is an `@MainActor` class protocol (`static id`, optional
  `configSection`, `init(context:) throws`, `register(into: inout ModuleRegistry)`).
  `ModuleLoader` creates the enabled modules in list order. A failed init, a bad config section,
  a duplicate module id or a rejected contribution becomes a `ModuleIssue` (logged, kept in
  `AppState.issues` for `vocoder doctor`). These are never fatal for the app.
- **Registry**: one typed list per extension point. Ids are unique within a point, the first
  registration wins, and each contribution is attributed to its module (`owner(of:in:)`).
  `ModuleContext` carries the module's parsed config section, a `SecretStore`, a `Log` and a
  read-only `ServiceContainer` (typed keys with defaults; only `now` so far). Features that
  modules offer each other go through registries, not services.
- **Tabs are split between Core and UI.** Core owns the `Tab` model: id, title, aliases,
  `TabBadge`, and lifecycle (`didActivate`/`didDeactivate`/`willClose`). It also owns
  `TabFactory` (with a placement: home → repo → integration) and `AppState`'s tab list and
  selection. `VoCoderUI` adds `ViewTab: Tab` (with a `body`). The only public way to build a
  `TabFactory` is `VoCoderUI`'s initialiser that takes `ViewTab`s. Core's initialiser and
  `ModuleRegistry.add(tabFactory:)` are `package`-level, so every tab the chrome sees can draw
  itself. `TabContent` still shows a note for a tab that isn't a `ViewTab` (fakes).
- **`AppCore`** holds the loaded modules, `AppState` and the `CommandRegistry`. `start()` opens
  the contributed tabs and collects attention items into `AppState`; `stop()` cancels
  collection and closes the tabs. `@Observable` `AppState` is the change stream. A separate
  event stream waits for a consumer that needs one.
- **Seams not built yet** are declared with identity only (`Provider.id`) plus capability
  option sets where DESIGN names them (`TaskTrackerCapabilities.iterations/.subtasks`). Members
  arrive with their WP. `Command` is minimal (id, title, category, `perform`); P1-05 extends it.
- **`LanguageModel`** has availability, prewarm, capabilities (`guidedGeneration`,
  `tokenCounting`), guided generation into a neutral flat `GenerationSchema` (string /
  integer / choice properties, optional or required), free-text `respond`, and `tokenCount`.
  It returns `GenerationOutcome.output | .noParse(reason)` and never throws. `withGenerationTimeout`
  enforces the request's timeout. Adapters validate output against the schema
  (`.decodingFailure` otherwise). The Foundation Models adapter (P2-05) maps the schema to a
  `DynamicGenerationSchema`.
- **Fakes get their own target, `VoCoderFakes`** (depends only on Core). It is used by tests,
  snapshot fixtures and the demo. `VoCoderTestSupport` keeps the contract suites (`Provider`,
  `TaskTracker`, `AttentionSource`, `SecretStore`, `Tab`, `LanguageModel`, `Module`).
  **`DemoModule`** (in `Sources/Modules/`) is the only module allowed to depend on the fakes.
  `vocoder --demo` loads just that module.
- **Composition root**: `Sources/vocoder/CompiledModules.swift` lists the module types. Until
  P1-07, `--demo` runs a temporary `DevShell` view (tab bar, tab content, attention, command
  list). Its tab digits and `q` are development keys, like the gallery's.
- **Boundary rules are checked**: `make lint` runs `scripts/check-deps.py` over
  `swift package dump-package`. Core depends on nothing of ours, modules depend only on
  Core/UI and never on each other, and only `DemoModule` may use the fakes.

## Consequences

- Adding Jira means a module target, an entry in `CompiledModules` and in `ModuleTests`. Core
  doesn't change.
- Module tabs are `@Observable` classes conforming to `ViewTab`. Badge or title changes
  re-render the chrome without any extra wiring.
- The P2-05 adapter must handle a dynamic schema. The P0-05 spike measured a static
  `@Generable` flat type. If the dynamic form routes worse, the adapter may specialise
  internally, but the neutral schema stays the interface.
- DESIGN §4.1 (targets), §4.10 (registry details) and §6 (contract tests, dependency check)
  updated; PLAN notes on P1-05, P1-06, P1-07 and P2-05.

## Alternatives considered

- **Tabs entirely in `VoCoderUI`** with an open, type-keyed registry for UI contributions. This
  is more general, but it adds an extension mechanism nothing else needs, and Core would lose
  tab identity for voice and attention.
- **Fakes stay in `VoCoderTestSupport`, and the executable links it.** This puts Swift Testing
  in the shipping binary.
- **`--demo` only prints the registered contributions.** That proves less. The dev shell is
  small and P1-07 replaces it.
- **Fully specified provider protocols now** (from DESIGN §4.5). Their shapes should come from
  the WPs that use them, with the real APIs in hand.

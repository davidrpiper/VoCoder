# 0009 — Config validation, Keychain secrets and `vocoder doctor`

- Status: Accepted
- Date: 2026-10-17
- WP: P1-06

## Context

P1-06 turns DESIGN §4.9 into code: the TOML config, secrets in the Keychain, the setup CLI and
`vocoder doctor`. A few things weren't settled by DESIGN v1 or ADR 0006:

- ADR 0006 made a bad module config section a non-fatal `ModuleIssue`. P1-06's acceptance wants
  invalid config reported, with actionable errors, *before* the TUI starts.
- DESIGN didn't say how modules are enabled, where the theme setting goes, or how
  `vocoder auth <module>` knows what to ask for.
- Doctor checks have to be contributed per module, so a new integration brings its own.
- The `vocoder` binary is ad-hoc signed, so its code identity changes with every build. The
  data-protection keychain needs entitlements a plain CLI doesn't have.

## Decision

- **Every config error stops startup.** That covers syntax, types, unknown sections and keys,
  repo paths, aliases, `[keys]` values, the theme and module sections. `vocoder` prints them all
  (file:line, key path, message, fix hint) and exits 1 without touching the terminal. The same
  list comes from `vocoder config check` and `vocoder doctor`. A module *init* failure stays a
  non-fatal `ModuleIssue` as in ADR 0006. Only config parsing moved earlier. A missing file means
  defaults, plus a toast pointing at `vocoder config init`. A missing file passed with
  `--config` is an error.
- **Sections:**
  - Core owns `[[repo]]` (`path`, `aliases`; other keys are allowed for modules, e.g.
    `linear_teams` in P4-04), `[keys]` (`leader`, `[keys.bindings]`), `[ui] theme` (`auto`,
    `dark` or `light`; a table, because top-level keys must come before every table in TOML),
    and `[modules] disabled`.
  - `voice`, `tasks` and `docs` are reserved for their WPs.
  - Each compiled-in module's id is its section. The module's `ConfigSection` decodes it, and it
    can list its `keys` so typos are caught. A section for a module that has no settings is an
    error.
- **Modules are enabled by default.** `[modules] disabled = [...]` turns compiled-in modules off.
- **Location:** `--config`, then `$VOCODER_CONFIG`, then `~/.config/vocoder/config.toml`.
- **TOMLDecoder stays behind `TOMLDocument`** (ADR 0004). Each section is decoded on its own, and
  `[[repo]]` entries one at a time, so a single run collects every error. Line numbers come from
  TOMLDecoder for syntax errors, and from a small locator over `[table]` / `key =` lines for
  everything else.
- **Modules declare their secrets** (`static var secrets: [SecretSpec]`: name, title, where to get
  it). `vocoder auth <module>` asks for each one with echo off (`--stdin` for scripts,
  `--remove`). Doctor checks that every enabled module's secrets are set. A missing secret is a
  warning, with the hint to run `auth` or disable the module.
- **Keychain:** `KeychainSecretStore` stores generic passwords in the login keychain, with service
  `dev.vocoder.<module>` and account = secret name. `SecretStore.hasSecret` reads attributes only,
  so doctor never triggers an access prompt. Values are never logged (tested). The real-Keychain
  contract test is opt-in (`VOCODER_KEYCHAIN_TESTS=1`, prefix `dev.vocoder.test`).
- **Doctor checks are an extension point**:
  - `DoctorCheck: Provider` (title, `async run() -> DoctorResult`: ok, skipped, warning or failure,
    plus message and hint), registered with `ModuleRegistry.add(doctorCheck:)`. It has a
    `FakeDoctorCheck`, and `DoctorCheckContract` requires a hint on every warning and failure.
  - `Doctor.run` runs the checks in order with a per-check timeout. A stuck check fails and the
    run goes on.
  - Built-in checks:
    - Core: config, modules, key bindings (`Keymap.issues`), secrets.
    - UI: terminal kind, Option-as-Meta (Terminal.app profile, Ghostty `macos-option-as-alt`),
      and whether macOS takes Ctrl-Space for input-source switching.
    - App: Apple Intelligence. It moves into the Foundation Models module in P2-05.
  - Module checks: Claude Code CLI presence and version, with a provisional minimum of 2.1.302
    (the P0-04 version, which P1-09 confirms).
  - Doctor loads the modules through `AppShell` exactly as the app does, without starting them, so
    keymap issues include the UI's navigation commands.

## Consequences

- A typo in the config can't silently disable a setting, but it also blocks startup until fixed.
  That's acceptable for a single-user tool. The messages say what to write.
- New modules get config, secrets and doctor support by declaring `configSection`, `secrets` and
  doctor checks. Core doesn't change.
- After a rebuild, the first *read* of a secret value may show a macOS "vocoder wants to access…"
  dialog, because the ad-hoc signature changed. Writes and attribute lookups don't. Signing with a
  stable identity (later packaging, P6-04) removes this.
- DESIGN §4.9 and the §4.10 table updated. ADR 0006's "bad config section → `ModuleIssue`" now
  only applies to module init.

## Alternatives considered

- **Config section errors as `ModuleIssue`s (ADR 0006 as written):** the app would start with a
  module silently unconfigured. That contradicts P1-06's acceptance, and problems would show up
  later and less clearly.
- **An explicit `enabled` list:** every new module would need a config edit before it shows up.
  Modules without accounts already start cleanly (module contract), so opt-out is enough.
- **Data-protection keychain:** needs `keychain-access-groups` entitlements and a provisioning
  profile, which a SwiftPM CLI doesn't have (`errSecMissingEntitlement`).
- **A top-level `theme` key:** works, but only above the first table, which is easy to get wrong
  when editing.

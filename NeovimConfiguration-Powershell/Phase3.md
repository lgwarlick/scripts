# Phase 3: Migrate regression tests to Pester

## Goal and boundaries

Replace the custom PowerShell test runner and assertions with Pester while
preserving every existing assertion, failure injection, real subprocess check,
and Lua integration check. This document is a plan; it does not implement the
migration or change bootstrap behavior.

The current harness contains 15 default scenarios and eight additional scenarios
enabled by `-PluginSource`, for 23 total. The default suite already requires
Neovim for argument quoting and preview checks; it is not a pure unit-test suite.
Pester must remain a development dependency, never a bootstrap runtime dependency.
Keep Windows x64 and Windows PowerShell 5.1 as the acceptance environment.

Use Pester **5.7.1** as the initial pinned version. Import that exact version and
fail with setup instructions if it is unavailable; do not silently use Windows'
bundled Pester or install modules during a test run. Its manifest declares a
PowerShell minimum below 5.1; actual compatibility must still be exercised on 5.1.
See the [versioned module manifest](https://raw.githubusercontent.com/pester/Pester/5.7.1/src/Pester.psd1).

## Suite layout and execution

- Keep `support/Test-Bootstrap.ps1` as the public entry point, preserving its
  optional `-PluginSource` parameter. Convert it into a thin runner that imports
  Pester, selects suites, supplies container data, and returns a nonzero process
  exit code for failed tests, discovery/setup errors, or missing prerequisites.
- Add `support/Bootstrap.Safety.Tests.ps1` for the 15 default scenarios and
  `support/Bootstrap.Integration.Tests.ps1` for the eight source-dependent
  scenarios. Use descriptive `Describe`, `Context`, and `It` blocks with stable
  scenario IDs from the inventory below. Helpers belong under `support` and must
  contain fixture construction only, not replacement copies of production logic.
- Without `-PluginSource`, run the safety suite and explicitly report that the
  integration suite was not selected. With it, run both suites and require all
  thirteen checkouts at the committed locks. Invalid or missing prerequisites
  must fail an explicitly requested suite rather than turn it into skipped tests.
- Retain the current README invocation forms. Produce console results and an
  NUnit XML report beneath the ignored `.validation` directory. Check the Pester
  result object for failures and zero executed tests; do not rely on printed PASS
  messages as evidence of success.
- Run suites sequentially in a fresh PowerShell process. Dot-source the bootstrap
  in `BeforeAll` without invoking its deployment entry point. Put filesystem and
  process work in setup/test/teardown blocks, never in Pester discovery code.
  Follow [Pester v5 test structure](https://pester.dev/docs/v5/usage/test-file-structure).

## Coverage inventory

Map each existing scenario to at least one Pester test. Preserve all assertions
inside each scenario, even where the table summarizes several checks. Splitting
a scenario into multiple tests is acceptable; matching the total count alone is
not proof of equivalent coverage.

| ID | Suite | Required behavior |
| --- | --- | --- |
| S01 | Safety | Parse the bootstrap, runner, new PowerShell tests, and helpers using the Windows PowerShell parser. |
| S02 | Safety | Real subprocess failure throws; `-AllowFailure` preserves exit code 7; a real timeout throws. |
| S03 | Safety | Real Neovim argv round trip preserves spaces, quotes, trailing backslashes, dollar expressions, backticks, and empty arguments. |
| S04 | Safety | Reject overlapping deployment paths and drive roots. |
| S05 | Safety | Equal inventories match; additional files and empty directories count as differences. |
| S06 | Safety | Accept plain settings and reject existing plugin-loading configuration without executing it. |
| S07 | Safety | Recovery before backup rename leaves original contents intact. |
| S08 | Safety | Recover a completed backup rename before its journal update; retain the backup. |
| S09 | Safety | Recover activation before its journal update; restore original contents and retain the failed candidate. |
| S10 | Safety | Failed first deployment moves aside only its own active candidate. |
| S11 | Safety | Recovery after the restoration rename is repeatable and clears the journal. |
| S12 | Safety | Refuse unrelated active content and forged transaction paths while preserving user files. |
| S13 | Safety | A real exclusive profile lock prevents a second writer. |
| S14 | Safety | Reject a real junction without traversing or changing its target. |
| S15 | Safety | Real child-process `-WhatIf` creates no artifacts, preserves inventories, suppresses hostile VIMINIT/EXINIT, and explains unchecked work. |
| I01 | Integration | Declined deployment preserves plain settings. |
| I02 | Integration | Full locked deployment over plain settings succeeds with spaces and Unicode paths and retains one backup. |
| I03 | Integration | A second deployment preserves configuration and lock contents, plugin revisions, backup count, and avoids repeated source preparation. |
| I04 | Integration | Real offline editor checks cover tree opening, no-formatter notice, diagnostics shortcut, pairing, buffer/path completion, snippets, Git signs inside/outside repositories, and ignored project-local `.lazy.lua`. |
| I05 | Integration | Injected live-verification failure restores modified settings and user files and retains the backup. |
| I06 | Integration | Modified managed checkout is rejected before configuration replacement and user files remain intact. |
| I07 | Integration | Injected verification failure on a clean first deployment leaves no failed configuration active. |
| I08 | Integration | Simulated absent Neovim requests the exact manifest package/version and install action, then performs a real clean-profile deployment. |

Keep `support/verify.lua` and `support/Test-Editor.lua` as real Neovim-side checks.
Preserve startup error capture, scheduled error notifications, expected plugin
inventory and initialization, disabled implicit installs/project specs, empty
tool registries, mappings, and the `BOOTSTRAP_VERIFIED` success marker. Pester
must assert both successful native exit and the success marker. Do not replace
these checks with mocked successful startup.

## Fixtures, mocks, and safety

- Give each test its own absolute filesystem fixture beneath a unique
  `.validation` run directory. Keep spaces/Unicode and shared data/state fixtures.
  Use physical paths rather than provider-only paths because native tools and
  production path validation require them. Retain artifacts and report their
  locations, matching current debugging behavior.
- Remove dependencies on test order. Tests needing an existing deployment must
  create one in their own setup. The repeat-run test performs both runs itself;
  modified-checkout tests create their own user-file sentinel. Mutate copies of
  plugin sources, never the supplied source directory.
- Capture and restore PATH, all four XDG home variables, NVIM_APPNAME, VIMINIT,
  EXINIT, and any additional process environment variables a fixture changes.
  Restore them in teardown even after failures, and dispose locks in `finally`.
  Ensure deployment tests use isolated XDG homes before invoking production code.
- Replace `Assert-Condition` and `Assert-Failure` with Pester assertions, preserving
  case-sensitive comparisons and expected exception messages. Replace manual
  function redefinitions with scoped `Mock` calls and parameter-filtered
  `Should -Invoke` checks; see [Pester v5 mocking](https://pester.dev/docs/v5/usage/mocking).
- Preserve current mock boundaries: block real package changes; simulate package
  presence and the 7-Zip probe; copy locked local sources instead of downloading;
  inject only the intended live-verification failure. Capture original native and
  configuration-check scriptblocks before mocking so all other invocations remain
  real. Keep Git identity/status checks, directory renames, journals, rollback,
  Neovim startup, and Lua assertions real.
- Pester mocks do not cross process boundaries. Keep the preview subprocess
  explicitly on `-WhatIf`; do not assume parent-process package mocks protect it.
  No test may invoke a real installer or change the default editor profile.

## Migration stages and acceptance

1. Record the current 15-scenario and full 23-scenario results on the supported
   Windows environment, including tool versions and local locked-source location.
   Maintain the inventory above as the assertion-by-assertion parity checklist.
2. Add Pester tests alongside the unchanged harness. Port safety scenarios first,
   then integration scenarios and their Lua invocation. Run old and new suites in
   separate processes with separate fixtures against the same locks and tools.
3. Require every mapped scenario to pass in both implementations with no skipped
   required cases. Verify the new runner returns nonzero for a deliberately failed
   assertion and a setup error, restores the environment after failure, and emits
   a usable report. Remove these temporary failure injections afterward.
4. Convert the original entry point into the thin Pester runner only after parity
   is demonstrated. Remove the custom assertion/runner implementations and manual
   mock replacements. Update the README with the pinned development dependency,
   setup steps, suite prerequisites, unchanged commands, and report locations.
   Record new execution evidence separately from historical Phase 1 validation.
5. Run both suite selections through the final entry point on Windows PowerShell
   5.1. Verify repository-tracked configuration/locks and the default profile remain
   unchanged. The migration is complete only when all inventory items and Lua
   checks pass through Pester and no retired harness code is needed.

CI can subsequently invoke the same runner on Windows, using a separately
provisioned supported Neovim/toolchain and exact locked sources. Keep dependency
downloads separate from offline test execution. Code coverage may be collected
for the PowerShell bootstrap as a diagnostic; it neither replaces the parity
checklist nor measures Lua coverage, and no arbitrary percentage is a migration
gate.

## Assumptions and remaining work

- Preserve the Phase 2 assumption that configuration and plugin data are always
  on the same volume. Do not add cross-drive support or cross-drive tests.
- The runtime-detection enhancement remains Phase 2 work. Preserve any regression
  tests added for it before migration; do not change production detection merely
  to adopt Pester. The 23-scenario inventory is the current minimum, not a ceiling.
- Actual installer/elevation/reboot behavior, real network interruption, and
  interactive rendering retain the acceptance limits documented in
  `compatibility/VALIDATION.md`. Historical download, Winget lookup, and health
  checks are not all automated by the current harness; retain that record and do
  not claim the migration automates or replaces those checks.

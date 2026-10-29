# Phase 2b: Bootstrap safety and regression coverage

Status: completed on 2026-10-29. All four changes passed isolated Windows
validation. Phase 3 remains a plan; the Pester migration has not started.

## Goal and boundaries

Resolve the four directory-review concerns before migrating tests to Pester.
Keep Windows x64 and Windows PowerShell 5.1 compatibility, existing invocation
forms, ShouldProcess behavior, and exact configuration/plugin locks. Use the
existing custom harness and disposable fixtures beneath `.validation`; do not
install packages, change the default profile, or implement language tooling.

## Changes and acceptance criteria

1. Extend unmanaged-runtime detection beneath `site` to include `ftplugin`,
   `autoload`, `lua`, `indent`, `syntax`, `compiler`, `colors`, `keymap`, `parser`,
   `queries`, and `spell`, alongside `pack`, `plugin`, `ftdetect`, and `after`.
   Reject existing directories conservatively, report their paths with remediation
   guidance, and never execute their contents or traverse reparse points.
2. Apply a single timeout budget to native-process execution and stdout/stderr
   collection. A parent exiting with inherited output pipes still open must time
   out rather than hang. Preserve normal output, failure codes, and AllowFailure.
   Retain best-effort process-tree termination and dispose process/stream handles.
   Guaranteed termination of already-orphaned descendants requires separate
   Windows Job Object support and is outside this phase.
3. Strengthen live-verification rollback coverage: compare complete configuration
   inventories, require one additional retained backup matching the original,
   retain the failed candidate, and require journal removal.
4. Strengthen repeat-run coverage: require identical inventory counts, path sets,
   and hashes; unchanged plugin revisions and backup count; and no additional
   source preparation.

## Validation and completion

- Parse PowerShell files under Windows PowerShell 5.1.
- Exercise unmanaged runtime directories and a junction without executing or
  changing existing contents. Preserve ordinary empty/shared data locations.
- Exercise a real exited-parent/inherited-output-pipe timeout with a bounded,
  self-terminating child and a scheduling tolerance.
- Run the default and full locked-source selections of `support/Test-Bootstrap.ps1`.
- Record results, artifact locations, tool versions, and remaining limitations here.
- Verify committed configuration/locks remain unchanged. Update `Phase3.md` only
  after acceptance passes, then stop before the Pester migration.

## Execution evidence

- Environment: Windows x64, Windows PowerShell 5.1.26100.9711, Neovim 0.12.6,
  and Git for Windows 2.56.0.windows.3.
- Parser validation passed for `NeovimConfiguration.ps1` and
  `support/Test-Bootstrap.ps1` under Windows PowerShell 5.1.
- Default selection: **17 scenarios passed**. Artifacts are retained beneath
  `.validation/t-f0e910e9`.
- Full selection: **25 scenarios passed**, including real Neovim startup/editor
  checks, complete repeat-run inventories and plugin revisions, and rollback
  inventories, retained backups/failed candidates, and journal removal. Artifacts
  are retained beneath `.validation/t-5bf1dbcd`.
- Both runs exercised all fifteen guarded runtime directories, preserved their
  contents, rejected a runtime junction without changing its target, and accepted
  missing/empty `site` and unused shared checkouts. The inherited-pipe regression
  used a five-second timeout, required return within eight seconds, verified that
  the parent had exited, and cleaned up its own self-terminating child.
- Full-suite sources were the thirteen existing locked checkouts beneath
  `.validation/download-910bf7cf`. No dependency downloads or package installations
  were performed; integration package presence/installation remained simulated.
- The real default-profile `-WhatIf` preview passed. Its configuration inventory
  matched the saved snapshot after validation. Committed configuration and the
  compatibility manifest/locks remained unchanged; `git diff --check` passed.

Commands used from the repository root:

```powershell
.\support\Test-Bootstrap.ps1
.\support\Test-Bootstrap.ps1 -PluginSource .\.validation\download-910bf7cf
.\NeovimConfiguration.ps1 -WhatIf
```

Tests ran in fresh `powershell.exe -NoProfile -ExecutionPolicy Bypass -File`
processes because this host blocks script files by default. This is a process-only
execution-policy option; the bootstrap does not change execution policy.

Timeout cleanup may spend up to one additional second waiting for a best-effort
process-tree termination command. It cannot guarantee termination of descendants
whose parent has already exited. Real installer/elevation/reboot acceptance and
language-tooling work remain outstanding as documented in
`compatibility/VALIDATION.md` and `Phase2.md`. No Pester migration was performed.

# Phase 1 validation record

Date: 2026-10-29. Baseline: `phase1-2026-10-29`.

## Environment and limits

Validation used Windows x64, Windows PowerShell 5.1, Neovim 0.12.6, Git for
Windows 2.56.0.windows.3, and GNU tar 1.35. The tested Neovim range is deliberately
limited to 0.12.6 (exclusive upper bound 0.12.7). It does not imply compatibility
with every 0.12 release or future plugin revisions.

No Winget installations/upgrades or changes to the default editor configuration
were performed. All deployment fixtures and plugin checkouts were placed under
the ignored `.validation` directory. The test processes used an explicit
process-only execution-policy option because this host blocks script files by
default; the bootstrap does not change execution policy.

This is isolated-profile validation on Windows, not completed disposable-machine
installer acceptance. Package presence and Neovim installation were simulated in
the integration harness. Actual Neovim/plugin initialization, configuration
replacement, Git revision checks, backups, and recovery were exercised.

## Executed checks

- Windows PowerShell parser validation and the dependency-free safety/recovery
  suite (`support/Test-Bootstrap.ps1`).
- Expanded 23-scenario suite with locked source checkouts, real headless startup,
  plain-settings replacement, repeat-run stability, and paths containing both
  spaces and a non-ASCII character.
- Native exit-code failures, bounded timeouts, and round-trip argument quoting for
  spaces, quotes, trailing backslashes, shell characters, and empty arguments.
- Read-only preview in a clean profile with hostile `VIMINIT`/`EXINIT`, verifying
  unchanged file inventories. Also ran the real default-profile `-WhatIf` preview.
- Unsupported existing plugin configuration, modified managed checkouts, overlapping
  paths, drive roots, junctions, additional files/directories, and exclusive locks.
- Recovery before/after backup rename, activation before journal update, interrupted
  restoration, unrelated active content, forged journal paths, failed first
  deployment, and injected final-verification failure. Retained backups and user
  files were checked after rollback.
- A simulated absent-Neovim package request used exact `Neovim.Neovim` version
  0.12.6 before a real clean-profile deployment. No package was actually installed.
- All thirteen source repositories were downloaded using the bootstrap's actual
  exact-commit fetch function and checked for commit, origin URL, ownership marker,
  inventory, and working-tree cleanliness.
- All eleven requested plugins and two Neo-tree dependencies initialized at their
  recorded revisions. Startup errors and scheduled error notifications fail the
  verification process explicitly.
- Functional checks exercised Neo-tree opening, the formatting-without-tools
  notice, diagnostics shortcut invocation, pair insertion, buffer/path completion,
  built-in snippet expansion, and Gitsigns inside and outside repositories, including
  a changed tracked file. A project-local
  `.lazy.lua` fixture was ignored. No external LSP/formatter/linter was claimed.
- Winget read-only lookups confirmed `Neovim.Neovim` 0.12.6, `Git.Git` 2.56.0.3,
  and `7zip.7zip` 26.05, including their vendor download locations. Source URLs and
  exact plugin commits are committed separately in the manifest and lockfile.

## Compatibility decisions and health reports

The Blink development branch required a new dependency; the committed baseline
instead selects stable v1.10.2, commit
`78336bc89ee5365633bcf754d93df01678b5c08f`. Its Lua matcher avoids binary downloads
and Rust. Snippet expansion infrastructure is available without a bundled snippet
collection.

Mason-LSPConfig refreshes registries during setup even with an empty installation
list. Empty Mason package/system registries prevent that network activity in
Phase 1. A later language-tooling phase must deliberately configure registries.
The full Mason health check also queries the latest upstream release; it was not
run as an offline acceptance check. Mason startup/order/settings and prerequisite
detection were checked separately; actual 7-Zip package presence was simulated.

Inspected health reports for Lazy, Mason-LSPConfig, Treesitter, Blink, and Conform.
Treesitter's standard installation directory is explicitly added to runtimepath
after Lazy's reset. Remaining expected findings are:

- Treesitter reports missing Tree-sitter CLI. Parser installation is deferred;
  initialization succeeds without installing the CLI or a compiler.
- Blink reports its native fuzzy library absent. The selected Lua matcher works
  without that library.
- Blink notes that provider availability can vary dynamically. LSP completion is
  deferred; buffer/path completion was exercised directly.

No parser updates, language-package installations, LuaRocks resolution, Rust builds,
or Blink binary downloads are part of startup or bootstrap preparation.

## Remaining release acceptance

Before releasing this as a machine-tested installer, use disposable Windows
machines to exercise actual absent/older Neovim and prerequisite installation,
registration association for upgrades, installer failures, elevation, reboot-required
results, PATH changes, missing Winget, unavailable pinned packages, and incompatible
installed tools. Test unsupported newer/unmanaged Neovim and ambiguous executable
resolution across those machines. Real network interruption and process termination
during deployment remain distinct from the injected failure/recovery fixtures.

Interactive terminal rendering and all language-specific LSP, formatting, linting,
and parser behavior remain outside the completed acceptance checks. No automated
test coverage percentage or fully validated system-installation matrix is claimed.

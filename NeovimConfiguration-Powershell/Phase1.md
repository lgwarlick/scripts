# Phase 1: Neovim installation and plugin foundation

Status: implemented; isolated Windows validation is recorded in
`compatibility/VALIDATION.md`. Disposable-machine installation acceptance remains
a release gate. Do not install packages on the user's workstation for validation.

## Goal and supported starting states

Build `NeovimConfiguration.ps1` into a repeatable Windows bootstrap for every
plugin in `CorePlugins.md` and `QualityOfLifePlugins.md`. Interpret
`nvim.lsp-config` as `neovim/nvim-lspconfig`.

Support two initial states: Neovim is absent, or Neovim is installed without a
plugin configuration. Also support repeated deployments produced by this script.
Do not migrate another plugin setup. Inspect existing configuration without
executing it; stop conservatively for unfamiliar/plugin-loading content. Back up
plain editor settings before replacement; do not merge arbitrary Lua.

Success requires a supported executable, verified prerequisites, exact plugin
revisions, and successful headless startup. Repeated runs preserve configuration
and lockfile contents without unnecessary backups, downloads, or package upgrades.
Language servers, formatters, linters, parsers, and language-specific configuration
are deferred. `LanguagePlugins.md` currently supplies no requirements.

## Compatibility and prerequisites

- Keep Windows PowerShell 5.1 compatibility, `SupportsShouldProcess`, `-WhatIf`,
  and `-Confirm`; target Windows x64 in 64-bit PowerShell.
- Commit exact Neovim/plugin revisions, supported version bounds, prerequisite
  package IDs/versions, architecture, sources, and review date in the compatibility
  manifest and lockfile. Validate actual startup; do not ship placeholder hashes
  or infer compatibility from versions alone.
- Select Neovim 0.12.6, minimum 0.12.6 and exclusive maximum 0.12.7. Preserve
  compatible installations. Install absent Neovim with exact `Neovim.Neovim`
  matching. Upgrade an older registered Winget installation only when its executable
  can be associated with the registration. Stop for newer unsupported versions,
  incompatible unmanaged installations, ambiguity, or unavailable package versions.
- Keep packages in `$resources` with `Name` and exact `Id` properties. Install
  missing Git and archive prerequisites only. Git for Windows supplies GNU tar
  and curl; 7-Zip supplies Mason archive support. Preserve prerequisites meeting
  the manifest's requirements; report incompatible tools for remediation.
- Defer the C compiler and Tree-sitter CLI with parser installation. Verify locked
  Treesitter setup works without them; disable parser installation/update hooks.
- Do not bootstrap Winget, alter execution policy, downgrade Neovim, or install
  unrelated SDKs. Stop for unsupported environments, reboot requirements, and native
  failures. Document downloads, agreement acceptance, and potential elevation.
- Rediscover executables after installation. Use the validated absolute Neovim
  executable throughout. Restore temporary process PATH changes; include verified
  tool directories in generated configuration for ordinary later sessions.

## Configuration and reproducibility

Keep Lua configuration, metadata, manifest, and lockfile as reviewable files.
Discover standard paths through a clean invocation suppressing user initialization,
plugins, and state writes. Deploy the default profile; reject nonempty `NVIM_APPNAME`.
Support spaces, non-ASCII names, and valid XDG path overrides.

| Plugin | Phase 1 behavior |
| --- | --- |
| lazy.nvim | Separately pinned bootstrap; manage explicit locked checkouts. |
| nvim-lspconfig | Native LSP definitions for a later phase. |
| mason.nvim | Empty package/system registries to prevent implicit refresh downloads. |
| mason-lspconfig.nvim | Load after Mason/lspconfig; empty installation list, automatic enabling off. |
| conform.nvim | No external formatters or automatic formatting. |
| nvim-treesitter | Eager initialization; no parser installation/update. |
| blink.cmp | Stable v1, Lua matcher, buffer/path completion, snippet expansion infrastructure; no snippet collection/binary download. |
| neo-tree.nvim | Locked plenary.nvim/nui.nvim dependencies and fallback symbols. |
| gitsigns.nvim | Basic Git change indicators inside repositories. |
| nvim-autopairs | Default pairing; no nvim-cmp integration. |
| nvim-lint | Empty linter configuration and no automatic triggers. |

Disable Lazy project-local specifications, implicit missing-plugin installation,
automatic updates, unused package/LuaRocks resolution, and build hooks. Download
only manifest repositories at exact commits during authorized preparation. Check
checkout identity, cleanliness, and repository URLs; refuse modified managed
directories. Baseline changes require repository changes and renewed validation.

Use Space as leader. Provide `Space e`, `Space f`, and `Space d` for the tree,
manual formatting, and diagnostic details. Explain when no formatter is configured.
Install `gd`, `gr`, `K`, `Space rn`, and `Space ca` on LSP attachment. Use Blink's
default preset. Add no theme, font, snippet collection, or unrelated customization.

## Deployment, rollback, and interruption recovery

- Serialize deployment/recovery by resolved profile. Require Neovim to be closed.
  Guard package actions and grouped preparation/deployment/recovery with
  `ShouldProcess`; declining required work stops dependent operations.
- Resolve local absolute paths. Reject drive roots, network paths, junctions,
  symbolic links, and overlapping configuration/control/data/cache/staging/backup
  locations. Permit Windows' exact shared data/state path. Inspect reparse points
  without traversing them.
- Prepare/check configuration in isolated configuration/data/cache/state locations,
  with a controlled working directory/environment. Bound subprocess execution and
  inspect asynchronous setup errors before reporting success.
- Publish plugins to a dedicated owned data directory per configuration baseline.
  Never change shared checkouts. Check candidates against permanent plugin paths;
  retain previous baselines so rollback preserves plugin compatibility.
- Compare complete file/directory inventories. Back up differing supported settings
  through a collision-safe dated sibling rename, retaining all user files. Exact
  matches require no replacement or backup.
- Persist an atomic journal before replacement, recording ownership, transaction ID,
  target/staging/backup paths, original presence, and phase. Activate through sibling
  staging and directory renames.
- On failure, restore prior settings or move aside only this run's first-install
  candidate. Retain backups/failed candidates. Stage restoration outside the active
  path so interrupted copying cannot expose partial configuration.
- Recover uncommitted transactions under the profile lock on the next normal run.
  Account for termination between rename and journal update and after restoration.
  Stop for manual inspection if ownership, paths, or active content are ambiguous.
- Retain installed system packages and prepared baselines after failure. Report
  failures, artifact/backup locations, and rerun guidance. Never delete unrelated
  Neovim data or report success after failed native work.
- Preview must not install packages, download plugins, create directories/logs,
  write journals, recover transactions, or run user configuration. Describe pending
  recovery and checks that require installation.

## Validation and release gates

Parse PowerShell under Windows PowerShell 5.1; validate Lua and real plugin startup
against the committed baseline. Cover clean/configured preview, declined actions,
full deployment, repeat runs, spaces/Unicode, modified checkouts, extra user files,
profile locks, and failed activation/restoration. Inject interrupted transactions
at rename/journal boundaries. Test native failures/timeouts and offline startup.

Exercise tree navigation, completion, pairing, Git signs, diagnostics/formatting
shortcuts, and expected deferred-tool health warnings. Do not claim working LSP,
formatting, linting, or newly installed parser support without external tools.

Before release, test actual absent/older/incompatible Neovim and prerequisite
installations on disposable Windows machines. Include newer versions, ambiguous
PATHs, missing Winget, unavailable pinned packages, network failures, installer
elevation, and reboot outcomes. Record executed and untested scenarios honestly.
Complete the README and parent script index with installation/recovery guidance.

Exact revisions and upstream evidence live in `compatibility/baseline.json` and
`config/lazy-lock.json`; execution evidence lives in `compatibility/VALIDATION.md`.

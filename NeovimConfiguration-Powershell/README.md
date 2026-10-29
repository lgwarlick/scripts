# Neovim configuration bootstrap for Windows

`NeovimConfiguration.ps1` installs Neovim when absent and deploys a locked plugin
foundation and the [Phase 2 language configuration](LanguagePlugins.md) for YAML,
Azure Pipelines, Terraform, PowerShell, Bash, and JSON/JSONC. It supports Windows x64,
64-bit Windows PowerShell 5.1 or later, and
Neovim **0.12.6**. Other releases require a reviewed compatibility-baseline change.

Start with either no Neovim installation or Neovim without a plugin configuration.
An empty configuration directory or simple `init.lua`/`init.vim` editor settings
are supported. Existing plugin setups are outside this script's migration scope.
Inspection is conservative and never executes existing configuration; unfamiliar
files, directories, or plugin-loading statements cause an actionable stop.

## Run

Close Neovim, then run from this directory:

```powershell
# Read-only preview; no configuration, package, plugin, or backup changes.
.\NeovimConfiguration.ps1 -WhatIf

# Confirm package changes and the grouped configuration deployment.
.\NeovimConfiguration.ps1 -Confirm

# Perform the same deployment without per-action confirmation prompts.
.\NeovimConfiguration.ps1
```

Use a PowerShell session whose execution policy permits this script under your
organization's rules. The script does not change execution policy. Clear
`NVIM_APPNAME` first; alternate Neovim profiles are unsupported. Paths come from
the selected Neovim executable, including applicable XDG environment overrides.
Junctions, symbolic links, network paths, and overlapping deployment paths are
rejected. Paths with spaces and non-ASCII characters are supported.

`-WhatIf` can identify executables and configuration paths but cannot verify
downloads or plugin startup. When Neovim is missing, destination checks remain
pending until installation. Declining a required action stops dependent work.
Deployment approval also covers necessary rollback and pending recovery.

## Software, downloads, and permissions

Winget is required only when a package must be installed or upgraded. The script
does not install Winget. Packages are matched exactly against the `winget` source:

| Package | Version installed when needed | Existing installation policy |
| --- | --- | --- |
| `Neovim.Neovim` | 0.12.6 | Preserve 0.12.6. Upgrade older registered Winget installations only when the executable can be associated with the registration. Stop for newer or incompatible unmanaged installations. |
| `Git.Git` | 2.56.0.3 | Preserve Git >= 2.19.0; require its GNU tar capability and a working curl executable. |
| `7zip.7zip` | 26.05 | Preserve 7-Zip >= 19.0; find it on PATH or under Program Files. |

Git for Windows supplies GNU tar and curl. The Windows-provided bsdtar is not
accepted as GNU tar. The generated configuration adds verified tool directories
to Neovim's child-process PATH, so a developer shell and permanent PATH edits are
unnecessary. Temporary bootstrap PATH changes are restored on exit.

Winget downloads vendor installers, accepts source and package agreements, and
may request administrator elevation. Neovim's package may also install the
Microsoft Visual C++ runtime. Reboot-required outcomes stop the bootstrap with
instructions. Already installed packages remain installed after later failures.

Plugin sources are downloaded over HTTPS from the GitHub repositories listed in
[the compatibility manifest](compatibility/baseline.json), at the exact commits in
[lazy-lock.json](config/lazy-lock.json). There are no automatic plugin updates,
project-local `.lazy.lua` specifications, LuaRocks resolution, Rust builds, or
Blink binary downloads. The script refuses to overwrite modified managed checkouts.

Language prerequisites (Node.js/npm, PowerShell 7, Terraform CLI, Tree-sitter CLI,
and Clang with a Windows SDK) are installed separately. Versions and installation
instructions are in [LanguagePlugins.md](LanguagePlugins.md). After deployment,
run `:BootstrapInstallTools` explicitly to download pinned Mason tools and compile
parsers, then restart Neovim. Startup and `-WhatIf` never install language tools.

## Included behavior

All eleven requested plugins are included, with plenary.nvim and nui.nvim as
Neo-tree dependencies and a pinned SchemaStore catalog. Mason has an explicit,
pinned registry; automatic installation and automatic server enabling remain
disabled. The configuration explicitly enables available servers. Conform provides
manual formatting; TFLint runs on Terraform read/save, and Treesitter highlights
supported buffers after parsers have been provisioned.

Blink supplies LSP/buffer/path completion and Neovim's snippet expansion infrastructure,
using its Lua matcher. No snippet collection is included. Neo-tree uses fallback
symbols without requiring a Nerd Font. Gitsigns and autopairs use their normal
basic behavior. No theme or font is installed.

| Shortcut | Action |
| --- | --- |
| `Space e` | Toggle the file tree |
| `Space f` | Manual formatting; explains when no formatter is configured |
| `Space d` | Diagnostic details |
| `gd`, `gr`, `K` | Definition, references, hover, after an LSP attaches |
| `Space rn`, `Space ca` | Rename and code actions, after an LSP attaches |
| `Ctrl-Space`, `Ctrl-n` / `Ctrl-p`, `Ctrl-y` | Open completion, select, accept (Blink default preset) |

Language features require successful provisioning. General YAML and Azure files
use mutually exclusive servers; project-specific pipeline/template globs are
documented in [LanguagePlugins.md](LanguagePlugins.md). PowerShell uses its LSP
formatter with `Space f`; all other selected languages use Conform's external tools.

## Backups, repeats, and recovery

The default configuration is normally `%LOCALAPPDATA%\nvim`. Before replacing
differing supported settings, the entire directory is renamed to a sibling named
`nvim.backup-<UTC timestamp>-<unique id>`. Backups include all user files and are
retained after successful deployment or restoration. Settings are replaced, not
merged. Exact matching configurations require no backup on a repeat run.

Plugins live in a separate owned baseline directory beneath
`stdpath('data')\neovim-bootstrap`. Configuration changes receive a separate
baseline, so restoring an older configuration preserves its plugin dependencies.
Preexisting shared plugin directories are never modified or deleted. Source
revisions are checked before and after startup; automatic upgrades are disabled.

A sibling `nvim.bootstrap-control` directory contains a profile lock, preparation
workspaces, and the atomic transaction journal. Only one bootstrap can deploy to
the profile at a time. A later run recovers an interrupted, uncommitted deployment
before proceeding. Failed candidates and preparation artifacts are retained and
reported; successfully prepared plugin baselines are also retained for reuse.
Recovery never recursively deletes an existing user's configuration or data.

For manual recovery, close Neovim, move the current configuration aside, then copy
the reported dated backup to the original configuration path. Keep the backup
until startup succeeds. If the journal or paths cannot be validated, the script
stops for manual inspection rather than guessing. Preserve the journal and use its
recorded paths to resolve the interruption before rerunning. Do not delete the
entire Neovim data directory as a repair step. Old workspaces/baselines may be
removed manually only after confirming no configuration or retained backup needs them.

## Validation

See [the validation record](compatibility/VALIDATION.md) for executed checks and
remaining machine-installation tests. No real packages were installed to validate
this implementation. The committed baseline is checked against isolated Windows
profiles; installer/elevation/reboot scenarios still require disposable-machine
acceptance testing before release.

```powershell
# Safety and recovery checks; writes disposable fixtures only under .validation.
.\support\Test-Bootstrap.ps1

# Also run real Neovim deployment checks using already downloaded locked sources.
.\support\Test-Bootstrap.ps1 -PluginSource C:\path\to\locked-checkouts
```

The optional source directory must contain all fourteen repository checkouts named
as in the lockfile. Integration checks simulate package presence and copy those
checkouts; they never install software or touch the default editor profile.

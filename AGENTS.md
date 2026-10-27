# Repository Guidelines

## Project Structure & Organization

This repository contains standalone utility scripts. Give each script its own descriptive directory containing its source and a README. Currently, `DevOpsBootstrap-Powershell/` contains `DevOpsBootstrap-Powershell.ps1` and its usage guide. The root `README.md` is the script index; add a linked, one-to-three-sentence overview whenever introducing a script. No shared modules, test directories, or asset directories currently exist.

## Development & Validation Commands

There is no build step or dependency installation required for editing. Run these commands in PowerShell from the repository root:

```powershell
# Preview proposed tool installations and upgrades.
.\DevOpsBootstrap-Powershell\DevOpsBootstrap-Powershell.ps1 -WhatIf

# Run installations and upgrades, confirming each change.
.\DevOpsBootstrap-Powershell\DevOpsBootstrap-Powershell.ps1 -Confirm
```

The bootstrap script requires Windows and PowerShell 5.1 or later. Normal execution changes installed software. `-WhatIf` still performs Winget lookups when available, but skips installation and upgrade commands; it cannot confirm upgrade availability.

## Coding Style & Naming Conventions

Prioritize human readability. Use four-space indentation, descriptive variable names, and approved PowerShell Verb-Noun function names such as `Install-Winget`. Prefer explicit cmdlet names over aliases and use parameter splatting for long commands. Explain non-obvious behavior with short comments.

Keep configurable tools in the `$resources` collection using `Name` and exact Winget `Id` properties. Preserve `SupportsShouldProcess`, `-WhatIf`, and `-Confirm` behavior around changes. Keep Windows PowerShell 5.1 compatibility. No formatter or linter is configured.

## Testing Guidelines

No automated testing framework or coverage target is configured. Validate PowerShell syntax with `System.Management.Automation.Language.Parser.ParseFile`, then preview relevant changes with `-WhatIf`. For installation changes, exercise missing tools, installed tools, no available upgrade, and failures in a disposable Windows environment. Report checks performed and any untested paths; do not run real installations merely to validate documentation edits.

## Commits & Pull Requests

Existing history uses short descriptive subjects, such as `powershell bootstrap`; no strict commit format is established. Write concise, action-oriented subjects. Pull requests should explain the problem, changed behavior, validation performed, and any installation or permission implications. Link relevant issues when available and update affected READMEs alongside behavior changes.

## Security & Configuration

Do not commit credentials or machine-specific configuration. Preserve exact package matching and restore temporary environment settings. Document downloads, agreement acceptance, and administrator requirements in each script's README.

# DevOps Bootstrap (PowerShell)

Installs missing development tools and upgrades installed tools through Winget.

## Requirements

- Windows with support for Winget (App Installer).
- Windows PowerShell 5.1 or later, or PowerShell 7.
- Internet access for package lookups and downloads. Installing Winget also requires access to the PowerShell Gallery and Microsoft's Winget release downloads.
- Permission to install the selected tools. Some installers may request administrator approval.

## Included tools

| Tool | Winget package ID |
| --- | --- |
| Git | `Git.Git` |
| Azure CLI | `Microsoft.AzureCLI` |
| AWS CLI | `Amazon.AWSCLI` |
| Terraform | `Hashicorp.Terraform` |
| OpenCode CLI | `SST.opencode` |
| Codex | `OpenAI.Codex` |

## Run the script

From the repository root, open PowerShell and run:

```powershell
.\DevOpsBootstrap-Powershell\DevOpsBootstrap-Powershell.ps1
```

Or, from this directory:

```powershell
.\DevOpsBootstrap-Powershell.ps1
```

Open a new terminal after installation to pick up changes to PATH. Rerun the same command whenever you want to check the configured tools for upgrades.

If PowerShell blocks the script, check your execution policy and follow your organization's policy for running local scripts.

## Preview with -WhatIf

From the repository root:

```powershell
.\DevOpsBootstrap-Powershell\DevOpsBootstrap-Powershell.ps1 -WhatIf
```

This skips Winget installation and all tool installation or upgrade commands.

- If Winget is available, the script runs its version check and installed-package lookups, then shows the proposed install or upgrade action for each tool. These lookups can contact Winget sources and accept source agreements.
- An `upgrade` preview means the tool is installed. It does **not** confirm that a newer version is available, because the upgrade command is skipped.
- If Winget is missing, the script previews the bootstrap action and stops. It cannot check the remaining tools without Winget.

To request confirmation before each change instead:

```powershell
.\DevOpsBootstrap-Powershell\DevOpsBootstrap-Powershell.ps1 -Confirm
```

## How it works

1. **Prepare Winget.** If `winget.exe` is missing, install the NuGet provider and `Microsoft.WinGet.Client` module for the current user as needed. Use `Repair-WinGetPackageManager -Latest` to install Winget, then locate its executable. Temporary TLS settings used during bootstrap are restored afterward.
2. **Verify Winget runs.** Run `winget --version`. If Winget cannot be installed or cannot run, stop before processing tools. An existing but broken Winget installation is reported rather than automatically repaired.
3. **Check each tool.** Use `winget list` with an exact package ID and the `winget` source. Detection uses Winget's installed-package records rather than the command's presence on PATH.
4. **Install or upgrade.** Run `winget install` for a missing package, or `winget upgrade` for an installed package. Winget determines whether an applicable upgrade exists. No applicable upgrade is a normal outcome.
5. **Report failures.** Warn when a tool fails and continue with the remaining tools. After the loop, throw an error listing any failed tools.

Package and source agreements are automatically accepted for install and upgrade operations. Winget prompts are disabled; installer UI or elevation prompts may still appear. Only the listed packages are processed. The script does not force upgrades of packages with unknown versions or override Winget pins.

## Add or remove tools

Edit the `$resources` collection near the top of `DevOpsBootstrap-Powershell.ps1`.

First, find and verify the tool's exact Winget package ID:

```powershell
winget search --name "PowerShell" --source winget
winget show --id Microsoft.PowerShell --exact --source winget
```

Then add a new entry inside the existing `$resources = @( ... )` block:

```powershell
[pscustomobject]@{ Name = 'PowerShell'; Id = 'Microsoft.PowerShell' }
```

- `Name` is the friendly name printed in progress messages.
- `Id` is the exact Winget package identifier, including its capitalization.
- Entries run in their listed order. Progress totals adjust automatically.
- Remove an entry to stop managing that tool; this does not uninstall it.

Run with `-WhatIf` after editing to review the proposed actions. New entries use the same install and upgrade workflow; no additional processing code is needed.

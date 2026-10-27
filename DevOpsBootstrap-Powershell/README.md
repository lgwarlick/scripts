# DevOps Bootstrap (PowerShell)

Installs missing development tools and upgrades installed tools through Winget, then installs or updates yamllint through Python's pip.

## Requirements

- Windows with support for Winget (App Installer).
- Windows PowerShell 5.1 or later, or PowerShell 7.
- Internet access for package lookups and downloads. Installing Winget also requires access to the PowerShell Gallery and Microsoft's Winget release downloads.
- Access to PyPI (or your configured pip package index) to install yamllint and its dependencies.
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
| Neovim | `Neovim.Neovim` |
| Python 3.13 | `Python.Python.3.13` |

Yamllint is installed separately with Python 3.13's pip, using `--user --upgrade`. It is not a Winget resource.

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

This skips Winget installation, all tool installation or upgrade commands, and PATH changes.

- If Winget is available, the script runs its version check and installed-package lookups, then shows the proposed install or upgrade action for each tool. These lookups can contact Winget sources and accept source agreements.
- An `upgrade` preview means the tool is installed. It does **not** confirm that a newer version is available, because the upgrade command is skipped.
- If Winget is missing, the script previews the bootstrap action and stops. It cannot check the remaining tools without Winget.
- If Python 3.13 is installed, the script previews the pip operation. Otherwise, it explains that yamllint setup depends on Python. Neither case queries available yamllint updates or previews the exact PATH addition.

To request confirmation before each change instead:

```powershell
.\DevOpsBootstrap-Powershell\DevOpsBootstrap-Powershell.ps1 -Confirm
```

## How it works

1. **Prepare Winget.** If `winget.exe` is missing, install the NuGet provider and `Microsoft.WinGet.Client` module for the current user as needed. Use `Repair-WinGetPackageManager -Latest` to install Winget, then locate its executable. Temporary TLS settings used during bootstrap are restored afterward.
2. **Verify Winget runs.** Run `winget --version`. If Winget cannot be installed or cannot run, stop before processing tools. An existing but broken Winget installation is reported rather than automatically repaired.
3. **Check each tool.** Use `winget list` with an exact package ID and the `winget` source. Detection uses Winget's installed-package records rather than the command's presence on PATH.
4. **Install or upgrade.** Run `winget install` for a missing package, or `winget upgrade` for an installed package. Winget determines whether an applicable upgrade exists. No applicable upgrade is a normal outcome.
5. **Set up yamllint.** Locate Python 3.13 through its Windows registry entry, check pip, and run `python -m pip install --user --upgrade yamllint` with that exact interpreter. Verify yamllint runs, then add its executable directory to the user PATH if needed. This PATH change has its own `-Confirm` prompt and also updates the current process.
6. **Report failures.** Warn when a tool fails and continue with the remaining tools. After processing Winget tools and yamllint, throw an error listing any failed tools.

Package and source agreements are automatically accepted for install and upgrade operations. Winget prompts are disabled; installer UI or elevation prompts may still appear. Only the listed packages are processed. The script does not force upgrades of packages with unknown versions or override Winget pins.

Python 3.13 is managed explicitly, even if another Python version is installed. The script does not select an activated project environment. It requires pip to be present in Python 3.13; a missing pip installation is reported as an error. Updating Python within the 3.13 series keeps yamllint tied to the same interpreter family.

## Check YAML with yamllint

After bootstrap, run:

```powershell
yamllint --version
yamllint -f parsable .\config.yaml
yamllint .
```

The first command verifies installation, the second checks a file with file/line/column diagnostics, and the third checks YAML files in the current directory. Yamllint checks syntax and lint rules; it does not replace an application's configuration validator. A repository's `.yamllint` file can customize lint rules. See the [yamllint documentation](https://yamllint.readthedocs.io/en/stable/quickstart.html).

If you decline the PATH change, use Python 3.13's full executable path with `-m yamllint` instead. Open a new terminal for other applications to pick up an accepted PATH change.

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

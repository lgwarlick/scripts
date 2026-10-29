# Phase 2 language tooling

The bootstrap deploys the configuration; language downloads are an explicit second
step. After installing the prerequisites below, open the generated configuration
and run `:BootstrapInstallTools`, then restart Neovim. The command refreshes the
pinned Mason registry, installs the exact packages in [tools.json](config/tools.json),
and compiles the six parsers. It stops at the first failure; inspect `:MasonLog`,
correct the cause, and rerun. Completed downloads remain available. Matching Mason
versions and existing parsers are reused. There are no startup installs, automatic
updates, or format-on-save hooks.

| Language | Server | Manual formatting (`Space f`) | Diagnostics |
| --- | --- | --- | --- |
| YAML | `yamlls` | Prettier | YAML syntax and SchemaStore schemas |
| Azure pipeline definitions and templates | `azure_pipelines_ls` | Prettier | Azure schema and pipeline rules |
| Terraform / tfvars | `terraformls` | `terraform fmt` through Conform | LSP plus TFLint on read/save |
| PowerShell | `powershell_es` | LSP formatting | PSScriptAnalyzer bundled with Editor Services |
| Bash | `bashls` | shfmt through Conform | ShellCheck through Bash LS only |
| JSON / JSONC | `jsonls` | Prettier | LSP syntax and SchemaStore schemas |

Blink provides the LSP completion source and capabilities for every server. Bash
LS formatting is disabled to keep Conform as the only shfmt route. PowerShell
falls back to its LSP formatter; other languages use only their external formatter.
Treesitter highlighting starts for installed YAML, Terraform, HCL, PowerShell,
Bash, and JSON parsers. JSONC uses the JSON parser, which supports comments in
the selected grammar; the acceptance runner includes a commented `tsconfig.json`.

## Prerequisites on Windows x64

The reviewed versions are recorded in `tools.json` and checked by executing each
tool before downloads. Version mismatches stop provisioning; review the baseline
before changing these pins. The PowerShell 5.1 bootstrap remains supported;
**Editor Services uses PowerShell 7 (`pwsh.exe`)**, not Windows PowerShell 5.1.

| Prerequisite | Version | Winget ID |
| --- | --- | --- |
| Node.js LTS and its npm | 26.13.0 | `OpenJS.NodeJS.LTS` |
| PowerShell 7 | 7.6.9 (Winget package 7.6.9.0) | `Microsoft.PowerShell` |
| Terraform CLI | 1.16.6 | `Hashicorp.Terraform` |
| Tree-sitter CLI | 0.27.1 | `tree-sitter.tree-sitter-cli` |
| LLVM / Clang | 23.1.4 | `LLVM.LLVM` |

Install those packages using your organization's normal process. For example:

```powershell
winget install --id OpenJS.NodeJS.LTS --exact --source winget --version 26.13.0
winget install --id Microsoft.PowerShell --exact --source winget --version 7.6.9.0
winget install --id Hashicorp.Terraform --exact --source winget --version 1.16.6
winget install --id tree-sitter.tree-sitter-cli --exact --source winget --version 0.27.1
winget install --id LLVM.LLVM --exact --source winget --version 23.1.4
```

Restart the shell after installing. `node`, `npm`, `pwsh.exe`, `terraform`,
`tree-sitter`, and `clang` must resolve on Neovim's inherited PATH. Standard
locations include `C:\Program Files\nodejs`, `C:\Program Files\PowerShell\7`,
`C:\Program Files\LLVM\bin`, and the user's Winget Links directory. A PATH entry
alone is insufficient: provisioning executes each prerequisite and checks its
version, catching broken portable links too. The selected Treesitter revision
requires CLI >= 0.26.1; the pinned CLI is installed as a native package, not npm.
For Windows parser compilation, supply the Visual Studio C++ Build Tools and
Windows SDK, and run Neovim from the corresponding x64 developer shell. Clang is
selected through a temporary `CC` setting, restored even if compilation fails.
SDK/linker availability is verified by successful parser compilation.

Winget prerequisites may require administrator elevation and vendor agreements.
The bootstrap does not install these prerequisites automatically. Mason downloads
Node packages from npm and release archives from GitHub/HashiCorp; parser sources
come from the repositories/revisions in the locked Treesitter parser table. Mason
uses the existing Git/GNU tar/curl/7-Zip foundation. Node package transitive
dependencies and live remote schema contents are not independently locked.
PowerShell script execution must be permitted by your organization's policy;
the configuration does not bypass or change execution policy or load profiles.

## YAML selection and schemas

Default Azure rules match `azure-pipelines.yml`, `azure-pipelines.yaml`, and YAML
files anywhere beneath an `azure-pipelines/` directory. A repository containing
an entry point still uses `yamlls` for unrelated YAML. Put pipeline templates
under that directory or list their paths explicitly. For other locations create
`.nvim-azure-pipelines.json` at the project root:

```json
["ci/custom.yml", "ci/templates/**/*.yml", "ci/templates/**/*.yaml"]
```

These are slash-separated, case-sensitive globs relative to that root; `**`
includes nested paths. Only JSON string arrays are read; project Lua is never
executed. Restart attached clients after editing rules (`:lsp restart`). The
same patterns select the Azure client and its schema associations. General
`yamlls` refuses those buffers, so only one YAML server attaches. Use explicit
template patterns rather than marking the whole repository as pipelines.

General YAML and JSON use the pinned SchemaStore catalog. YAML's own catalog
integration is disabled [as SchemaStore recommends](https://github.com/b0o/SchemaStore.nvim).
Azure files use Microsoft's
[pipeline schema](https://github.com/microsoft/azure-pipelines-vscode/blob/master/service-schema.json)
and dedicated server for local template navigation. Schema URLs may require
network access on first use. Inspect `:lsp info` to confirm the selected client.

## Version pins and acceptance

New SchemaStore code is locked in `lazy-lock.json`; Mason's registry release and
all ten language packages are pinned in `tools.json`. Parsers inherit exact
source revisions from the existing locked Treesitter plugin. Tools and parsers
live in `plugin_root/tools` and `plugin_root/parsers`, preserving dependencies
for backed-up configurations. Changing any config source changes baseline
identity. Configuration and data are assumed to share a volume.

Run the offline safety/editor suite first. After provisioning tools, run the
online acceptance checks against that generated configuration:

```powershell
.\support\Test-Bootstrap.ps1 -PluginSource C:\path\to\locked-checkouts
.\support\Test-Languages.ps1 -Config "$env:LOCALAPPDATA\nvim"
```

The second command copies the supplied configuration into a disposable profile
under `.validation`, reuses its provisioned tools, and creates isolated fixtures.
It tests each server's attachment, completion request, diagnostics, formatting,
and parser/highlighter; pipeline entry points, templates, custom filenames, and
local template definitions are included. It makes no installations. Successful
completion requests alone do not establish the quality of schema suggestions;
also inspect YAML/JSON schema completions and invalid-property diagnostics
interactively, along with TFLint warnings and ShellCheck/PSScriptAnalyzer output.
Terraform provider-aware diagnostics require a separately initialized fixture
project; this repository never runs `terraform init` or `apply` automatically.

See [VALIDATION.md](compatibility/VALIDATION.md) for executed checks and outstanding
acceptance. Package discovery verifies availability, not successful installation
or end-to-end language compatibility.

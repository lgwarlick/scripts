# Phase 2 follow-up

## Existing runtime detection

Completed in [Phase 2b](Phase2b.md). The original check omitted executable runtime
directories such as `site/ftplugin`, allowing an existing `lua.lua` to execute
when a Lua buffer opened. Detection now guards the additional standard runtime
directories, with isolated regression checks for preserved contents and junction
rejection. The language-tooling work below remains planned.

## Deployment assumption

Assume configuration and plugin data locations are always on the same volume.
Cross-drive deployment will never occur in the supported environment, so no
change for cross-drive directory moves is planned.

## Language tooling

Prioritize YAML, Terraform, PowerShell, Bash, and JSON/JSONC. Record the selected
tools and their requirements in `LanguagePlugins.md` during implementation.
The existing LSP, Mason, Conform, nvim-lint, and Treesitter plugins provide the
integration foundation; separate language-specific Neovim plugins are not
required for this baseline.

| Language | Language server (Neovim configuration name) | Formatting | Diagnostics |
| --- | --- | --- | --- |
| YAML | [yaml-language-server](https://github.com/redhat-developer/yaml-language-server) (`yamlls`) | Prettier | Language-server schema validation |
| Azure Pipelines YAML | [azure-pipelines-language-server](https://github.com/microsoft/azure-pipelines-language-server) (`azure_pipelines_ls`) | Prettier | Azure Pipelines schema validation |
| Terraform | [terraform-ls](https://github.com/hashicorp/terraform-ls) (`terraformls`) | `terraform fmt` | Language-server diagnostics plus [TFLint](https://github.com/terraform-linters/tflint) |
| PowerShell | [PowerShell Editor Services](https://github.com/PowerShell/PowerShellEditorServices) (`powershell_es`) | Language-server formatting | PSScriptAnalyzer integration |
| Bash | [bash-language-server](https://github.com/bash-lsp/bash-language-server) (`bashls`) | `shfmt` | ShellCheck through the language server |
| JSON / JSONC | [vscode-json-language-server](https://github.com/neovim/nvim-lspconfig/blob/master/lsp/jsonls.lua) (`jsonls`) | Prettier | Language-server schema validation |

Add [b0o/SchemaStore.nvim](https://github.com/b0o/SchemaStore.nvim) for YAML and
JSON schema associations, completion, and validation. Configure explicit schema
mappings where particular YAML dialects require them. When supplying YAML
schemas through this plugin, disable the YAML server's built-in SchemaStore
catalog integration as described in the plugin documentation.

### General YAML and Azure Pipelines YAML

`yamlls` is an editor language server; Azure Pipelines YAML is a particular use
of YAML with Microsoft-defined structures such as `stages`, `jobs`, `steps`, and
`parameters`, plus pipeline expressions and template rules. Valid YAML is not
necessarily a valid Azure pipeline. See the
[Azure Pipelines YAML schema reference](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/?view=azure-pipelines).

Use `yamlls` for general YAML and `azure_pipelines_ls` for Azure pipeline
definitions and templates. Microsoft's server is a fork of Red Hat's YAML server
and supports navigation to locally referenced templates. General `yamlls` can
also use the Azure schema for schema-based completion and validation, but the
dedicated Azure server is the selected approach for pipeline files.

Configure explicit filename or directory rules to select exactly one YAML
language server per buffer. Include pipeline templates as well as entry-point
files; do not classify every YAML file in a repository as an Azure pipeline
merely because the repository contains `azure-pipelines.yml`. Allow project-specific
patterns for nonstandard pipeline and template locations. Configure schema
associations for those patterns and exclude the same files from general
`yamlls` attachment to avoid overlapping diagnostics. See the
[Neovim Azure Pipelines server configuration](https://github.com/neovim/nvim-lspconfig/blob/master/lsp/azure_pipelines_ls.lua).

Validate general YAML, an Azure pipeline entry point, a referenced local template,
and a nonstandard pipeline filename. Confirm the intended server attaches,
schema completion and diagnostics work, local template navigation works, and
both YAML servers never attach to the same buffer.

### Configuration requirements

- Enable Treesitter parsers for `yaml`, `terraform`, `hcl`, `powershell`, `bash`,
  and `json`. Validate JSONC highlighting with the selected parser baseline.
- Add Blink's `lsp` completion source and pass its capabilities to the language
  servers. The current configuration enables only path, snippet, and buffer
  sources.
- Configure explicit Mason tool installation and language-server enabling;
  automatic installation and server enabling are currently disabled. Configure
  the required Mason registries deliberately, since Phase 1 uses empty registries.
- Use Conform for the external formatters and nvim-lint for TFLint. Keep ShellCheck
  diagnostics in Bash Language Server rather than also invoking it through
  nvim-lint and producing duplicate diagnostics. Bash Language Server integrates
  with both ShellCheck and shfmt; choose one formatting route per buffer.
- Update `Space f` to support PowerShell's LSP formatter even when no Conform
  formatter is configured. Its current early return and `lsp_format = "never"`
  prevent this. Keep formatting manual initially, preserving the current shortcut
  behavior without introducing format-on-save.
- Document Node.js, the selected PowerShell host, Terraform CLI, and each external
  tool's installation requirements. Verify compatible versions and Windows
  execution paths during implementation, and pin newly introduced dependencies
  consistently with the existing compatibility baseline.
- Validate server attachment, completion, diagnostics, formatting, and parser
  behavior for each supported language using isolated fixtures. Preserve the
  existing bootstrap safety and recovery checks while extending language coverage.

Formatter support is documented in [Conform](https://github.com/stevearc/conform.nvim).
ShellCheck and shfmt integration is documented in
[Bash Language Server](https://github.com/bash-lsp/bash-language-server).

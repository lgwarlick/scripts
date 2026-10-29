# Scripts

A collection of useful scripts. Each script lives in its own directory with instructions for setup and use.

## [DevOps Bootstrap (PowerShell)](DevOpsBootstrap-Powershell/README.md)

Installs missing development tools and upgrades installed tools through Winget, including Git, Azure CLI, AWS CLI, Terraform, OpenCode, Codex, Neovim, and Python. It installs or updates yamllint through Python's pip, installs Winget when needed, and supports `-WhatIf` to preview proposed actions.

## [Neovim Configuration (PowerShell)](NeovimConfiguration-Powershell/README.md)

Installs Neovim when absent and deploys a locked plugin foundation on Windows, starting from an installation without plugin configuration. Supports read-only previews, dated configuration backups, and interrupted-deployment recovery; language tools and parsers are deferred.

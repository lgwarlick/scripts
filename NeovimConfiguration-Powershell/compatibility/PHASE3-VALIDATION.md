# Phase 3 validation

Date: 2026-10-29. Migration and final public-runner acceptance completed.
Historical Phase 1 and Phase 2b evidence remains in its original documents.

## Environment and frozen baseline

- Windows x64; 64-bit Windows PowerShell 5.1.26100.9711; Neovim 0.12.6;
  Git for Windows 2.56.0.windows.3; Pester 5.7.1.
- Pester was downloaded separately from PowerShell Gallery into ignored
  `.validation/modules/Pester/5.7.1`. Windows PowerShell's bundled Pester 3.4.0
  was preserved. No system module or application package was installed.
- Existing locked sources: `.validation/download-910bf7cf`, containing all thirteen
  checkouts. Tests copy these sources and perform no dependency downloads.
- HEAD was `d33e4aec9a89938be0f2726dc42c28bc8c8307bc`. Phase 2b changes were
  already present in the working tree, including modified production code,
  harness, README and phase documents, plus untracked `Phase2b.md`. Those changes
  were preserved; no commit was created.
- The original harness snapshot, HEAD, SHA-256 hashes, and baseline run logs are
  retained in `.validation/phase3-baseline`. The harness hash and mappings for
  all 67 original assertion call sites are recorded in
  [PHASE3-PARITY.md](PHASE3-PARITY.md). Loops and compound assertions retain all
  their checks; assertion-call counts are not a coverage gate.

## Executed checks

| Selection | Result | Retained artifacts |
| --- | --- | --- |
| Original harness, default | 17 passed | `.validation/t-fd4bf0d6` |
| Original harness, locked sources | 25 passed | `.validation/t-e84b22cd` |
| Pester safety during migration | 17 passed | `.validation/p-ca56497e` |
| Final public runner, default | 28 passed; no failed/skipped cases; exit 0 | `.validation/p-39e61976/results.xml` |
| Final public runner, locked sources | 36 passed; no failed/skipped cases; exit 0 | `.validation/p-08d170e6/results.xml` |

The default selection includes the original 17 safety scenarios and 11 runner
contract cases. The full selection additionally includes the original eight
integration scenarios, each with its own isolated filesystem/profile fixture.
The repeat-run scenario performs both deployments itself; rollback and modified
checkout scenarios construct their own initial deployments and user-file sentinels.

Runner contracts execute real child PowerShell processes through the same
Pester executor/result gate. They verify passing and deliberately failing
assertions, setup/discovery errors, missing and empty selections, skipped and
partially skipped scenarios, parseable NUnit reports, restoration of every
fixture environment variable after failure, and nonzero prerequisite failures.
The public-wrapper regression verifies exit forwarding and literal source paths
containing Unicode, apostrophes, dollar/backtick characters, and a trailing slash.
Expected failures are confined to disposable contract suites; they are not
failures or skipped cases in the selected acceptance suite.

The final read-only audit passed: all eight PowerShell scripts parse under 5.1;
production, configuration, manifest, locks and Lua verifier match the frozen
SHA-256 hashes; all thirteen supplied source checkouts remain clean at the locks;
the default configuration inventory is unchanged; and both NUnit reports contain
exactly the expected successful cases. Audit output is retained in
`.validation/phase3-final-audit.log`. No retired harness implementation is used by
the new runner or tests. Existing Phase 2b working-tree changes were preserved.

## Migration findings

- The first complete Pester port passed 24 of 25 original scenarios. The
  absent-Neovim mock initially lost the production function's omitted `Action`
  default. The test now reads that default from the original function AST before
  mocking and distinguishes omission from an explicitly supplied action. The
  corrected I08 passed its focused real clean-profile deployment.
- Public-wrapper contracts caught Unicode loss and PowerShell stream conversion
  when launching nested PowerShell through the native invocation operator.
  Explicit UTF-8 stdout/stderr forwarding now preserves literal error paths;
  the caller's console encoding is restored in `finally`.
- The editor Git fixture explicitly disables commit signing. Its integration
  check now supplies an inherited signing requirement to verify that override.
- NUnit export reads Windows OS metadata through CIM. Sandbox access was denied;
  acceptance therefore runs outside the sandbox with ordinary CIM access.
  This is a test-reporting requirement, not an administrator requirement added
  to the bootstrap.
- The sandbox's alternate user identity also fails Git's ownership check for
  the existing source checkouts. The source audit used the same outside-sandbox
  identity as acceptance; no global Git trust settings were changed.

## Remaining limits

Actual installer/elevation/reboot behavior, real network interruption, guaranteed
orphan-process cleanup, interactive rendering, cross-drive deployment, and Phase 2
language tooling retain their previously documented scope and acceptance limits.
Pester migration does not replace those release checks or claim Lua code coverage.

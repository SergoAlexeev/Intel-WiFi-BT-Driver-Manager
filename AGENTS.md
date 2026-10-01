# Agent instructions

## Start here
This is a Windows PowerShell driver manager. Read [README.md](README.md), the relevant parts of [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), and [docs/TESTING.md](docs/TESTING.md) before changing behavior. UI rules and examples are in [docs/console-ui-2.2.0.md](docs/console-ui-2.2.0.md); command details are in [DOCUMENTATION.md](DOCUMENTATION.md).

At the 2026-10-01 audit, main contained v2.1.0; v2.2.0 development was on feature/intel-graphics-preview in PR #1. Confirm the current branch and PR before editing. Do not assume preview features exist on main. Issues #2 (managed cache cleanup), #4 (coverage/sources), and #5 (console UI) hold the roadmap; do not duplicate their checklists in new documents.

## Implementation
- Preserve Windows PowerShell 5.1 compatibility. PowerShell 7 alone is not sufficient validation.
- Keep PowerShell files containing Cyrillic in UTF-8 with BOM. Avoid case-only variable name distinctions: PowerShell is case-insensitive.
- Use targeted changes; inspect status and diff, preserve unrelated work. In API-only work, read current blobs and review the resulting content/commit diff.
- Do not dot-source IntelWiFiBTManager.ps1 for tests: it starts its main flow. Existing tests extract functions through the PowerShell AST.
- Localized RU/EN messages must be neutral and understandable. Use “Проверка версий”, not first-person narration. State the effect of consent and refusal. Empty confirmation input must decline.
- Preserve standalone manager behavior when tools/ is absent. Helper scripts that require adjacent modules need the full repository.
- New hardware support must use applicable IDs/OS evidence, not a test laptop model or a larger version number alone.

## Trust and side effects
- Read-only comparison is not installation approval. PASS on a hash or CAT, an INF match, and an official-looking URL are separate evidence.
- Keep REJECT, UNVERIFIED and MANUAL_REVIEW semantics. Never promote a preliminary candidate report into automatic installation.
- The existing Wi-Fi/Bluetooth installer is external FirstEverTech code. Its PSGallery metadata checks are not signature verification. Do not describe it as an Intel product.
- Do not run the default manager, -Graphics or -Silent as a test: these can launch installers. -Silent explicitly bypasses interactive installation consent in the existing product; it is not a dry run.
- Never invoke a real restart in tests. Interactive restart requires explicit consent; preserve postponement.
- Delete only owned per-run temporary files, not user-supplied installers, logs, another active run, or the retained SignTool installation.
- Network integration tests are opt-in; SignToolCab.Integration.ps1 automatically answers yes and provisions tools. See TESTING.md before execution.

## Workflow and completion
Use the requested Issue as scope. For substantial changes, write a short plan in the Issue/PR; no separate ExecPlan framework is currently required.
Run relevant safe tests and parse changed scripts; use the Windows CI for platform validation. Report unrun checks and manual hardware limits honestly. A green CI is not a driver-installation certification.
Update documentation when behavior changes. Keep logs, packages, serial numbers, tokens and personal machine paths out of commits.
Update an Issue checkbox only with matching implementation and verification evidence. Keep published releases separate from preview work. Commit/push within the authorized task scope; do not merge, tag or release without authorization for that action.

# Findings

## 2026-05-06

- Upstream repository: `mattpocock/skills`.
- README says setup can be started with `npx skills@latest add mattpocock/skills`
  and lists engineering/productivity skills such as `diagnose`,
  `grill-with-docs`, `tdd`, `to-prd`, and `zoom-out`.
- Local worktree already had unrelated changes before this task:
  `.gitignore`, `AGENTS.md`, `prompts/review/adversarial-review.md`,
  deleted `init-codex-fj.sh`, and untracked `init-codex-openai.sh`.
- Existing `.codex_home` had `planning-with-files`; `.codex_home_api2/skills`
  existed but had no non-system skill found by the initial check.
- Installed these non-deprecated Matt Pocock skill directories into both Codex
  homes: `diagnose`, `grill-with-docs`, `improve-codebase-architecture`,
  `setup-matt-pocock-skills`, `tdd`, `to-issues`, `to-prd`, `triage`,
  `zoom-out`, `caveman`, `grill-me`, `write-a-skill`,
  `git-guardrails-claude-code`, `migrate-to-shoehorn`, `scaffold-exercises`,
  `setup-pre-commit`, `edit-article`, and `obsidian-vault`.

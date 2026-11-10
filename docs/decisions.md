# Decisions

One row per decision. Never rewrite an old row: a reversal is a new row that names the one it replaces.

The design rulings for the game itself live in the design docs (`docs/combat-design.md` and the proposals it names); this file starts with the move onto the shared working rules on 2026-11-10.

| ID | Decision | Reason | Chosen against |
| --- | --- | --- | --- |
| D1 | The project moves onto the owner's shared working rules (Tonttu84/ai-workflow) as a **solo** project: commits go to `main` and are pushed once the local gate is green. Commit messages follow Conventional Commits from here on, checked by the ai-workflow `commit-msg` and `pre-push` hooks in `.githooks/` (installed with `hooks/install.sh` in its default mode; a fresh clone turns them on with `make setup`) and by CI. `.githooks/*` keeps LF endings in `.gitattributes`, since Linux bash rejects CRLF scripts and this repo is checked out with `autocrlf`. The kind is the owner's choice (2026-11-10); the hook mode and the LF line are the agent's. | The owner moves every active project onto one way of working (ai-workflow D23). *The clone had no hooks of its own, so the default mode switches nothing off.* | *The `--git-hooks` mode (per clone only, nothing committed for CI to reuse); keeping the old prose commit subjects.* |

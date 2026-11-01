# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The full Phase 1 build plan — project context, working agreement, tech decisions, target repo layout, verified CMS API facts, the ordered slices, and the progress checklist — is imported here and is the source of truth:

@.claude/docs/phase-1-plan.md

## Key rules from the plan (summary)

- **One slice per session**, only the slice the Developer names. Explain the plan first and wait for a go-ahead; build in small steps the Developer can run. Never scaffold folders or files for future slices.
- **Ask before adding any dependency** (name it, why, alternatives).
- The AI core is a plain Python library, `coverage_agent`. CLI, FastAPI, and later entrypoints are thin wrappers — no business logic in entrypoints.
- Relate Python/AI concepts to Node/TS equivalents when introducing them.
- When a slice's acceptance criteria pass: summarize, tick the checklist in `.claude/docs/phase-1-plan.md` §6, suggest a Conventional Commits message, and stop.
- Never commit secrets, `.env`, `data/` contents, generated PDFs, or raw LCD/article content (licensed).
- Don't guess external API shapes (CMS, Voyage, Anthropic, HAPI) — check official docs or call the endpoint.

## Current state (update as slices land)

- Slice 0.1 done: git repo on `main` with root `README.md`, `.gitignore`, `docs/`, and a self-documenting `Makefile` (add `## description` after a target name to list it in `make help`).
- Slice 0.2 done: root `docker-compose.yml` runs one `postgres` service (`pgvector/pgvector:0.8.6-pg17`, named volume `pgdata`, `pg_isready` healthcheck). Credentials come from root `.env` (template: `.env.example`, Postgres vars only so far); compose fails fast if they're missing. Port is published on `127.0.0.1` only (not the LAN); host port defaults to **5433** because the Developer's Mac already runs a Homebrew Postgres on 5432. The `vector` extension is available but not yet created (slice 0.5 migration). Make targets: `up` (`--wait` until healthy), `down`, `reset` (deletes volumes), `psql` (runs psql inside the container, so no host client needed).
- Slice 0.3 done: `services/coverage_agent/` is a `uv` package project (Python 3.12, `uv_build` backend, `src/` layout, `uv.lock` committed). No runtime dependencies yet; the `dev` group has `ruff`, `pytest` and `pre-commit`. Ruff config (`line-length = 100`, rules `E,F,I,UP,B`) and pytest config (`testpaths = ["tests"]`, `strict = true`) live in its `pyproject.toml`. Its only code is a placeholder `main()` (the `coverage-agent` script), covered by `tests/test_smoke.py`.
- Root `.pre-commit-config.yaml` runs `ruff-check --fix` and `ruff-format` on `services/coverage_agent/` files. The installed hook runs from `services/coverage_agent/.venv`; if a commit fails with "`pre-commit` not found", run `make test` (or `uv sync`) to recreate `.venv`, then commit again.
- **Ruff is pinned twice and must match:** `rev: vX.Y.Z` in `.pre-commit-config.yaml` (the hook's own ruff) and the `ruff` entry in `services/coverage_agent/uv.lock` (what `make lint` uses). Both are 0.17.3. To upgrade, run `uv --directory services/coverage_agent add --dev ruff==X.Y.Z` and set `rev: vX.Y.Z` to the same version. Don't use `pre-commit autoupdate` alone: it moves only `rev`, to the newest tag. Check for drift with `grep -A1 '^name = "ruff"' services/coverage_agent/uv.lock; grep 'rev:' .pre-commit-config.yaml`.
- Root `pyrightconfig.json` points Pylance/pyright at `services/coverage_agent/.venv` (the workspace opens at the repo root, so the editor otherwise can't see the installed package). Pyright is editor-only for now; it is not in `make lint` or CI.

## Commands

The root `Makefile` is the single entry point; `make help` lists all targets.

```
make up / down / reset / psql   # local Postgres (docker compose)
make lint                       # ruff check + format --check
make fmt                        # ruff format + check --fix
make test                       # pytest
```

The Python targets wrap `uv --directory services/coverage_agent run ...`, which syncs `.venv` from `uv.lock` before running. Install the git hook once per clone with `uv --directory services/coverage_agent run pre-commit install`. To run a single test, from `services/coverage_agent/`: `uv run pytest tests/test_smoke.py::test_main_prints_greeting`.

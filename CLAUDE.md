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
- `services/coverage_agent/` is a fresh `uv init --package` project (Python 3.12, `uv_build` backend, `src/` layout, no dependencies, no tests). Its only code is a placeholder `main()` exposed as the `coverage-agent` script.

## Commands

From the repo root, `make help` lists Make targets (`up`, `down`, `reset`, `psql` so far). Python commands run from `services/coverage_agent/` until Make targets wrap them:

```
uv sync                  # create .venv and install
uv run coverage-agent    # run the package entrypoint
```

Once slice 0.3 lands, the root `Makefile` is the single entry point (`make help`, `up`, `down`, `reset`, `psql`, `lint`, `fmt`, `test`, `migrate`, ...). A single test will run as `uv run pytest tests/path/test_x.py::test_name` from `services/coverage_agent/`.

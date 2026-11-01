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

- Not yet a git repository; no root `README.md`, `.gitignore`, `Makefile`, or `docker-compose.yml` yet (slice 0.1/0.2 work).
- `services/coverage_agent/` is a fresh `uv init --package` project (Python 3.12, `uv_build` backend, `src/` layout, no dependencies, no tests). Its only code is a placeholder `main()` exposed as the `coverage-agent` script.

## Commands

Run from `services/coverage_agent/` until the root Makefile exists:

```
uv sync                  # create .venv and install
uv run coverage-agent    # run the package entrypoint
```

Once slices 0.2–0.3 land, the root `Makefile` is the single entry point (`make help`, `up`, `down`, `reset`, `psql`, `lint`, `fmt`, `test`, `migrate`, ...). A single test will run as `uv run pytest tests/path/test_x.py::test_name` from `services/coverage_agent/`.

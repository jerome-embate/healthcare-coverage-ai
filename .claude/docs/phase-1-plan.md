# Healthcare Coverage AI — Phase 1 Build Plan (for Claude Code)

> **Hand-off document.** This file tells Claude Code what we are building, how the Developer wants to work, and the exact slices to build, in order. It lives at `.claude/docs/phase-1-plan.md`. The repo's root `CLAUDE.md` imports it with a bare `@` line, **not inside backticks** (imports in code spans are not loaded):
>
> ```
> @.claude/docs/phase-1-plan.md
> ```

---

## 1. Project context

**Healthcare Coverage AI** is a prior authorization copilot. A clinic's prior auth coordinator creates a case (patient, requested service, documents). The system checks each payer coverage criterion against the patient's evidence and returns **Met / Not met / Insufficient evidence**, with a rationale and a **citation to the exact page and passage**. A human reviews and can override everything.

**Phase 1 goal:** a working AI core that evaluates a case end-to-end on a laptop, on synthetic data, with measured accuracy.

**Definition of done for Phase 1:** one command evaluates any golden case; a minimal review screen shows cited results; the README shows retrieval and end-to-end eval numbers.

### Scope

- **Services (3):** CPAP for obstructive sleep apnea, home oxygen, and NIPPV for COPD (confirm the third in slice 1.6).
- **Knowledge base:** CMS Coverage API — all non-retired NCDs, plus LCDs and articles for the 3 services.
- **Patients:** Synthea synthetic patients served by a local HAPI FHIR server.
- **Case documents:** synthetic clinical PDFs and fax-like scans, generated with gold labels.

### Out of scope (Phase 2 — do not build)

Go API, gRPC, BFF, SQS worker, AWS deployment, Terraform, multi-tenancy, SSO, Stripe, HIPAA-ready hardening.

### Core design rule

The AI core is a **plain Python library** (`coverage_agent`) with functions like `ingest_policies()`, `process_document()`, `evaluate_case()`. FastAPI, the CLI, and later the gRPC server and SQS worker are **thin wrappers** around it. Never put business logic in an entrypoint.

---

## 2. Working agreement (Claude Code must follow this)

The Developer is an experienced backend/DevOps engineer (Node.js/TypeScript, AWS, Terraform, Kubernetes). **The Developer wants to build piece by piece and understand every component.** Therefore:

1. **One slice per session.** Work only on the slice the Developer names. Never scaffold files for future slices.
2. **Explain before coding.** At the start of a slice, give a short plan: what we'll build, files touched, new concepts involved. Wait for a go-ahead.
3. **Smallest useful step.** Produce code in small pieces (one function, one file), explain each, and let the Developer run it before moving on.
4. **Map to what the Developer knows.** When introducing Python or AI concepts, relate them to Node/TS equivalents where helpful (e.g. `uv` ≈ npm/pnpm, `pydantic` ≈ zod, `pytest` fixtures ≈ test setup hooks).
5. **Ask before adding dependencies.** Name the package, why it's needed, and alternatives.
6. **Stop at the acceptance criteria.** When they pass, summarize what was built and what was learned, then stop.
7. **Tick the progress checklist** (section 6) and suggest a commit message (Conventional Commits, e.g. `feat(policy): add CMS coverage client`).
8. **Never commit:** secrets, `.env`, raw LCD/article dumps (licensed content), generated PDFs, `data/` contents.
9. **Prefer clarity over cleverness.** Typed functions, Pydantic models at boundaries, small modules, docstrings on public functions.
10. **When unsure about an external API's exact shape** (CMS, Voyage, Anthropic, HAPI), check the official docs or call the endpoint and inspect the response. Do not guess parameter names.

---

## 3. Tech decisions (already made)

| Area | Choice | Notes |
|---|---|---|
| Language | Python 3.12+ | managed with `uv` |
| Agent framework | Pydantic AI | typed tools, structured outputs |
| LLMs | Claude Haiku (cheap steps), Claude Sonnet (determinations) | use current model IDs from Anthropic docs; keep them in config |
| Embeddings + rerank | Voyage AI | record model name + dimension on every embedding row |
| Database | Postgres 17 + pgvector | `pgvector/pgvector` image; vectors + full-text in one DB |
| ORM / migrations | SQLAlchemy 2.x + Alembic | |
| Document parsing | Docling | layout-aware, page + bounding-box provenance, OCR for scans |
| Patient data | Synthea → HAPI FHIR (`hapiproject/hapi` image) | Synthea runs in a Java Docker container; no local Java install |
| Observability | Logfire | trace every agent step, tool call, tokens, cost |
| Evals | `pydantic-evals` + custom retrieval metrics | |
| API (Phase 1) | FastAPI | thin wrapper |
| Frontend (Phase 1, last) | Next.js + Tailwind + shadcn/ui + `react-pdf` | `apps/web` |
| Tooling | Ruff, Pytest, pre-commit, Makefile | |

### Repository structure (target shape — create folders only when a slice needs them)

```
healthcare-coverage-ai/
├── services/
│   └── coverage_agent/              # Python uv project
│       ├── src/coverage_agent/
│       │   ├── config.py            # pydantic-settings
│       │   ├── db/                  # SQLAlchemy models, session
│       │   ├── llm/                 # Claude client wrapper, disk cache, cost tracking
│       │   ├── policy/              # CMS client, sync, cleaning, sections, criteria
│       │   ├── documents/           # Docling parsing, OCR, classification, facts
│       │   ├── chunking/            # policy + clinical chunkers
│       │   ├── embeddings/          # Voyage client, batching, cache
│       │   ├── retrieval/           # vector, full-text, RRF, rerank, filters
│       │   ├── fhir/                # FHIR client used by agent tools
│       │   ├── agent/               # Pydantic AI agent, tools, output models
│       │   └── evals/               # retrieval + end-to-end eval runners
│       ├── api/                     # FastAPI (slice 8.3)
│       ├── cli/                     # command-line entrypoints
│       ├── migrations/              # Alembic
│       ├── tests/
│       │   └── fixtures/            # small sample API responses, sample PDFs
│       └── pyproject.toml
├── apps/web/                        # Next.js (slice 8.4)
├── scripts/                         # Synthea, FHIR loading, case generation
├── evals/
│   ├── retrieval/                   # question → expected chunk sets
│   ├── cases/                       # golden case specs + gold labels
│   └── runs/                        # run outputs (gitignored except summaries)
├── data/                            # raw downloads, generated PDFs (gitignored)
├── notebooks/
├── .claude/
│   └── docs/
│       └── phase-1-plan.md          # this file (Claude Code working docs)
├── CLAUDE.md                        # imports the plan
├── docs/
│   ├── policy-notes.md
│   ├── retrieval-results.md
│   └── adr/                         # architecture decision records
├── docker-compose.yml
├── Makefile
└── README.md
```

Note: the service folder and the Python package share the name `coverage_agent` (underscore): `services/coverage_agent/src/coverage_agent/`.

---

## 4. Known facts about the CMS Coverage API (verified)

- Base URL: `https://api.coverage.cms.gov`. No API key. Responses are JSON.
- Docs: `https://api.coverage.cms.gov/docs/swagger/index.html`.
- **NCD list:** `GET /v1/reports/national-coverage-ncd/` → `data[]` with `document_id`, `document_version`, `document_display_id`, `title`, `chapter`, `is_lab`, `last_updated`, `last_updated_sort`, `url`. `meta.next_token` signals pagination.
- Each row's `url` (e.g. `/data/ncd?ncdid=226&ncdver=3`) is the detail call: prefix with `/v1`.
- **NCD detail** fields include `item_service_description`, `indications_limitations`, `cross_reference`, `revision_history`, `effective_date`, `benefit_category`, `transmittal_url`; `meta.children` lists related endpoints (`related-ncas`, `other-versions`, ...).
- **Retired NCDs** are marked only in the title, inconsistently: `" - RETIRED"`, `"(RETIRED)"`.
- Use `last_updated_sort` (sortable, `20260812133308`), not `last_updated` (`MM/DD/YYYY`).
- **HTML in text fields is double-escaped** (`&lt;p&gt;`, `&amp;#160;`, `&sol;`). Unescape repeatedly until stable, then parse as HTML.
- Section headings are **bold paragraphs** (`<p><strong>B. Nationally Covered Indications</strong></p>`), not heading tags.
- **LCD and Article endpoints require a license token**: `GET /v1/metadata/license-agreement/` returns it; valid **1 hour**; send as `Authorization: Bearer <token>`.
- LCD list: `/v1/reports/local-coverage-final-lcds`. LCD detail: `/v1/data/lcd/` (+ `related-documents`, ...). Article detail: `/v1/data/article/` (+ `icd10-covered`, `hcpc-code`, ...). Confirm exact query parameters in Swagger.

**Respiratory NCDs (chapter 240):**

| NCD | document_id / version | Role |
|---|---|---|
| 240.4 CPAP Therapy for OSA | 226 / 3 | CPAP service |
| 240.4.1 Sleep Testing for OSA | 330 / 1 | defines valid sleep tests |
| 240.2 Home Use of Oxygen | 169 / 2 | home oxygen service |
| 240.9 NIPPV in the Home for CRF due to COPD | 380 / 1 | candidate third service |

Detailed documentation and continued-use criteria for DME are likely in the **DME MAC LCDs and policy articles** for positive airway pressure devices and oxygen equipment — find them in slice 1.5.

---

## 5. Slices

Each slice: **Goal → Steps → Acceptance criteria → Learn**. Do them in order.

---

### Milestone 0 — Foundations

#### Slice 0.1 — Repo skeleton

**Goal:** an empty but well-organized repo.

**Steps**
1. `git init`; create `README.md` (one-paragraph description + "Synthetic data only, not for clinical use"), `.gitignore` (Python, Node, `.env`, `data/`, `evals/runs/*` except summaries, `.venv`, `__pycache__`, `.ipynb_checkpoints`).
2. Create `docs/` (for project docs: ADRs, notes, results). The plan stays at `.claude/docs/phase-1-plan.md`; confirm the root `CLAUDE.md` imports it with a bare `@.claude/docs/phase-1-plan.md` line (not in backticks), and remove any "current state" notes in `CLAUDE.md` that this slice makes outdated.
3. Create a `Makefile` with a `help` target that lists targets.

**Acceptance:** `make help` prints targets; `CLAUDE.md` imports `@.claude/docs/phase-1-plan.md`; `git status` is clean after the first commit.

**Learn:** Makefile basics (tabs, `.PHONY`), why a Makefile is the single entry point.

#### Slice 0.2 — Postgres with pgvector

**Steps**
1. `docker-compose.yml` with a `postgres` service (`pgvector/pgvector`, Postgres 17), a named volume, env vars from `.env`, and a healthcheck (`pg_isready`).
2. Make targets: `up` (`docker compose up -d --wait`), `down`, `reset` (down + remove volumes), `psql`.

**Acceptance:** `make up` returns only when Postgres is healthy; `make psql` connects.

**Learn:** compose healthchecks and `--wait`.

#### Slice 0.3 — Python project

**Steps**
1. `uv init` a package project in `services/coverage_agent` with a `src/coverage_agent/` layout.
2. Add dev tools: Ruff (lint + format), Pytest. One trivial test.
3. `pre-commit` with Ruff hooks.
4. Make targets: `lint`, `fmt`, `test`.

**Acceptance:** `make lint && make test` pass.

**Learn:** `uv` vs npm mental model, `src/` layout, `pyproject.toml`.

#### Slice 0.4 — Configuration

**Steps**
1. `config.py` with a `Settings` class (`pydantic-settings`): `DATABASE_URL`, `ANTHROPIC_API_KEY`, `VOYAGE_API_KEY`, `LOGFIRE_TOKEN`, model IDs (`MODEL_FAST`, `MODEL_SMART`), `EMBEDDING_MODEL`.
2. `.env.example` with empty values; real `.env` gitignored.
3. A test that settings load from env.

**Acceptance:** importing settings with a missing required key fails with a clear error.

**Learn:** Pydantic models and validation (≈ zod).

#### Slice 0.5 — Database layer and migrations

**Steps**
1. SQLAlchemy 2.x engine + session factory in `db/`.
2. Alembic init in `services/coverage_agent/migrations`; first migration: `CREATE EXTENSION IF NOT EXISTS vector;`.
3. Make target `migrate`.

**Acceptance:** on a fresh volume, `make reset && make up && make migrate` succeeds; `\dx` shows `vector`.

**Learn:** Alembic revision workflow; why extensions belong in migrations.

#### Slice 0.6 — LLM wrapper, cache, and tracing

**Steps**
1. Configure Logfire at startup.
2. `llm/` wrapper: a function that calls Claude (fast model by default) and returns text + token usage.
3. A **disk cache** keyed by a hash of (model, prompt, params), enabled in dev, so repeated runs cost nothing.
4. A cost calculator from token usage (prices in config, not hard-coded in logic).
5. CLI: `uv run python -m cli.hello_llm` sends one prompt, prints answer, tokens, cost.

**Acceptance:** first run hits the API and appears in Logfire; second run is served from cache.

**Learn:** tracing basics, why caching matters for cost during development.

#### Slice 0.7 — CI

**Steps:** GitHub Actions workflow running `make lint` and `make test` on push/PR, with `uv` caching. No API keys needed.

**Acceptance:** green check on a pushed commit.

---

### Milestone 1 — Explore the policy data

#### Slice 1.1 — CMS client: basics

**Steps**
1. `policy/cms_client.py`: an `httpx` client with base URL, timeout, retries with backoff (ask before adding `tenacity`), a polite delay between requests, and a `get(path, params)` method.
2. Pagination helper that follows `meta.next_token` until empty.
3. Unit tests with `respx` (or similar) mocking HTTP — no real network in tests.

**Acceptance:** tests cover success, retry on 5xx, and pagination.

**Learn:** `httpx`, mocking HTTP in tests.

#### Slice 1.2 — License token

**Steps:** fetch the token from `/v1/metadata/license-agreement/`, inspect the real response shape first, cache it, refresh after ~55 minutes; `get(..., licensed=True)` adds the Bearer header.

**Acceptance:** a test proves the token is fetched once and reused, and refreshed after expiry (use a fake clock).

#### Slice 1.3 — NCD listing

**Steps**
1. Pydantic model `NcdListRow` for the list response fields.
2. `is_retired(title)` handling both title formats. Unit-test it.
3. Save a trimmed copy of a real list response as a test fixture.
4. CLI: `cli.list_ncds` prints counts (total, retired, lab) and the chapter-240 rows.

**Acceptance:** CLI output shows the 4 respiratory NCDs in section 4.

#### Slice 1.4 — Fetch respiratory NCDs

**Steps:** fetch detail for the 4 respiratory NCDs via each row's `url`; save raw JSON to `data/raw/ncd/<id>_v<version>.json`. Save the CPAP response as a test fixture.

**Acceptance:** 4 raw files on disk; fixture committed.

#### Slice 1.5 — Find and fetch the LCDs and articles

**Steps**
1. Call the final-LCDs report; search titles for positive airway pressure, oxygen, and non-invasive ventilation; list candidates with contractor info.
2. With the Developer, pick the DME MAC LCDs for the 3 services.
3. Fetch each LCD, its related documents, the related articles, and the articles' code tables (covered ICD-10, HCPCS). Save raw to `data/raw/lcd/` and `data/raw/article/` (gitignored — licensed).

**Acceptance:** raw LCD + article files exist for all 3 services; a short list of their IDs is recorded in `docs/policy-notes.md`.

#### Slice 1.6 — Study the data

**Steps:** a notebook in `notebooks/01_policy_exploration.ipynb` that loads the raw files and shows: which fields hold text, section structure, where criteria live, list nesting, how articles link to LCDs, what code tables look like. Write findings in `docs/policy-notes.md`. Confirm the third service.

**Acceptance:** `policy-notes.md` explains, per service, where the criteria are and how the text is structured.

**Learn:** reading real-world regulatory data; why exploration comes before chunking design.

---

### Milestone 2 — Policy ingestion v1 (naive)

#### Slice 2.1 — Raw storage and sync loop

**Steps**
1. Tables (Alembic): `policy_documents` (cms id, type NCD/LCD/article, display id, title, chapter, is_lab, retired), `policy_versions` (document id, version, effective date, last_updated_sort, content hash, superseded flag, `raw jsonb`, needs_processing).
2. `sync_ncds()` implementing: one list call → skip retired → skip if version and `last_updated_sort` unchanged → fetch detail → hash normalized content → if hash unchanged, update timestamp only → else store new version, supersede old, mark `needs_processing`.
3. Same pattern for the scoped LCDs and articles (`sync_lcds()`), using config from `config/policy_sources.yaml` (keywords, exclude retired).
4. CLI `cli.ingest_policies --stage sync`; Make target `ingest-policies`.

**Acceptance:** first run stores all non-retired NCDs + scoped LCDs/articles; an immediate second run makes **1 list call per document type and 0 detail calls** (log the counts).

**Learn:** extract-then-transform; idempotent sync with change detection.

#### Slice 2.2 — HTML cleaner

**Steps**
1. `unescape_fully(text)`: `html.unescape` in a loop until stable.
2. Parse with BeautifulSoup; convert to Markdown (ask before adding `markdownify`), preserving ordered lists and nested lettered lists; normalize non-breaking spaces and `\r\n`.
3. Tests using the CPAP fixture: output contains a numbered list with nested `a.`/`b.` items under section B.

**Acceptance:** cleaned CPAP text reads like the policy, with list structure intact.

#### Slice 2.3 — Section splitter

**Steps:** split cleaned text into sections using bold `A.`/`B.`/`C.`/`D.` headings; map fields → sections (`item_service_description` → A, `indications_limitations` → B/C/D). Keep `revision_history` and `cross_reference` out of embeddable text (store cross-references as document relationships).

**Acceptance:** tests on all 4 respiratory NCDs return the expected section labels; malformed HTML doesn't crash.

#### Slice 2.4 — Policy chunker

**Steps**
1. Parent chunk = a section; child chunks = one top-level list item **including its sub-items**; prose paragraphs grouped to a target size.
2. Tag Coverage with Evidence Development content as `ced` (excluded from default retrieval).
3. Chunk metadata: document id, version, display id, section, item number, effective date, `chunking_strategy`.
4. Deterministic chunk IDs (hash of version id + position + content).

**Acceptance:** CPAP section B produces one child chunk per numbered item; item 5 (AHI thresholds) contains both sub-items; CED chunk tagged.

#### Slice 2.5 — Code tables

**Steps:** relational tables for article code tables (covered ICD-10 codes, HCPCS codes, linked to article and LCD). Load them from raw JSON. These are **not embedded**.

**Acceptance:** a SQL query answers "is code X covered under article Y?".

**Learn:** when not to use vector search (exact identifiers).

#### Slice 2.6 — Embeddings and vector storage

**Steps**
1. `embeddings/` Voyage client: batching, `input_type` document vs query, disk cache, cost logging.
2. `policy_chunks` table: `content`, `context` (nullable, used in M6), `embedding vector(<dim>)`, `embedding_model`, generated `tsvector` column, parent id, metadata; HNSW index (cosine) + GIN index.
3. CLI `cli.ingest_policies --stage process` cleans → sections → chunks → embeds everything marked `needs_processing`.

**Acceptance:** all chunks embedded; rerunning processes nothing new.

#### Slice 2.7 — Naive search

**Steps:** CLI `cli.search_policies "<query>" --k 5` embedding the query and printing top-k with score, document, section, item. Exclude retired and CED by default.

**Acceptance:** for 5 hand-written questions (e.g. "minimum AHI for CPAP", "which home sleep test types are acceptable"), the right section appears in the top 3. Record the 5 questions; they seed the M6 eval set.

---

### Milestone 3 — Criteria extraction

#### Slice 3.1 — Criterion model

**Steps:** Pydantic models: `Criterion` (id, service, text, type: threshold / documentation / diagnosis / procedural, `phase`: initial / continued, `logic` for any-of / all-of branches, required evidence, source chunk ids, `verified`). `criteria` table.

**Acceptance:** the CPAP AHI rule (≥15, or 5–14 with documented symptoms/conditions) can be represented with its OR branches.

#### Slice 3.2 — Extract for one service

**Steps:** structured extraction with Claude (Sonnet) over the CPAP NCD sections + its LCD → list of `Criterion`. Save as unverified. A small review CLI shows each criterion beside its source text and lets the Developer mark it verified or edit it.

**Acceptance:** CPAP has a verified initial-coverage criteria list.

**Learn:** structured outputs, extraction prompt design, human verification.

#### Slice 3.3 — Remaining services

**Acceptance:** all 3 services have verified criteria; extraction prompt and any manual edits are recorded in `docs/policy-notes.md`.

---

### Milestone 4 — Patients and synthetic cases

#### Slice 4.1 — Generate patients

**Steps:** `scripts/generate_patients.sh` downloads the Synthea jar and runs it in `eclipse-temurin:17` Docker with a fixed seed, population size, and age range (e.g. 50–80), FHIR R4 export enabled, output to `data/synthea/`.

**Acceptance:** rerunning with the same seed produces identical output.

#### Slice 4.2 — HAPI FHIR

**Steps:** add `hapi` to compose, backed by a separate `hapi` database in the same Postgres (check HAPI docs for datasource config); healthcheck. `scripts/load_patients.py` posts bundles. Make target `load-patients`.

**Acceptance:** `GET /fhir/Patient?_count=5` returns patients.

#### Slice 4.3 — FHIR client

**Steps:** `fhir/` functions: `get_patient`, `get_conditions`, `get_observations(code=...)`, `get_medications`, `get_encounters`, returning Pydantic models (keep only fields the agent needs). Tests against a recorded fixture.

**Acceptance:** for a chosen patient, functions return typed results.

**Learn:** FHIR resources and search parameters.

#### Slice 4.4 — Case spec and gold labels

**Steps:** a YAML format in `evals/cases/` describing a case: patient id, service, intended outcome, per-criterion intended status, which documents to generate and what evidence each contains (incl. which page). `cases` and `gold_labels` tables plus a loader.

**Acceptance:** one handwritten CPAP case spec loads into the DB.

#### Slice 4.5 — Document generator

**Steps:** `scripts/generate_case_documents.py`: for a case spec, Claude writes clinical documents (sleep study report, physician note, referral) consistent with the patient's FHIR data and the intended evidence; render to PDF (ask before choosing a PDF library). Record gold evidence location (document + page).

**Acceptance:** generated PDFs read as plausible documents and contain the intended evidence on the recorded pages.

#### Slice 4.6 — Fax degradation

**Steps:** convert selected PDFs to images, apply rotation, noise, blur, low DPI, re-wrap as PDF; mark `is_scanned`.

**Acceptance:** degraded files look like faxes yet remain human-readable.

#### Slice 4.7 — Build the golden set

**Steps:** ~30 cases (10 per service), mixed ~40% approve / ~40% criterion not met / ~20% missing documentation. For CPAP include all AHI branches (≥15; 5–14 with documented condition; 5–14 with nothing documented; symptom only in a scanned note). Split dev/test.

**Acceptance:** all cases load; the Developer spot-checks 5 by hand.

---

### Milestone 5 — Document processing

#### Slice 5.1 — Parse one PDF with Docling

**Steps:** notebook + function `parse_document(path)` returning elements with text, type (paragraph, table, heading), page number, bounding box.

**Acceptance:** printed elements show correct pages and boxes for a generated PDF.

#### Slice 5.2 — Scans and OCR

**Steps:** detect scanned vs native (e.g. little or no extractable text); enable OCR only for scans; cache parsed output to avoid re-parsing.

**Acceptance:** degraded faxes parse to usable text; timings logged.

#### Slice 5.3 — Document classification

**Steps:** Haiku classifies each document (sleep study, progress note, referral, lab report, other) with a structured output; store `doc_type`.

**Acceptance:** correct type on all documents of 5 golden cases.

#### Slice 5.4 — Clinical chunker and storage

**Steps:** `case_documents` and `document_chunks` tables (case id, document id, page, `bbox jsonb`, text, context, embedding, tsvector). Chunk by page/section; **keep tables whole**; every chunk carries provenance. CLI `cli.process_case <case_id>`.

**Acceptance:** every chunk of every case document has page + bbox; searches are always filtered by `case_id`.

#### Slice 5.5 — Fact extraction (optional)

**Steps:** Haiku extracts key facts (e.g. AHI, SpO2, test date, test type) into a `facts` table linked to the source chunk.

**Acceptance:** facts match gold labels on the dev cases.

---

### Milestone 6 — Retrieval evals, then advanced retrieval

Rule: **measure after every change.** Record each result in `docs/retrieval-results.md`.

#### Slice 6.1 — Retrieval eval set

**Steps:** ~50 items in `evals/retrieval/`: query, scope (policy or case id), expected chunk(s) (by stable identifiers, not row ids). Start from the 5 questions in slice 2.7; add case-document questions using gold evidence locations.

#### Slice 6.2 — Runner and baseline

**Steps:** runner computing recall@k and MRR; `eval_runs` (config jsonb, git commit, timestamp, summary) and `eval_results` tables. Make target `eval-retrieval`. Record the baseline (vector only).

#### Slice 6.3 — Hybrid search

**Steps:** full-text search on the `tsvector` column; fuse with vector results via Reciprocal Rank Fusion in SQL. Measure.

#### Slice 6.4 — Reranking

**Steps:** rerank the top ~30 fused results with Voyage rerank; return top k. Measure, including added latency and cost.

#### Slice 6.5 — Contextual retrieval

**Steps:** Haiku writes 1–2 sentences of context per chunk using the full document as a **cached prompt prefix**; prepend to content for both embedding and tsvector; re-embed. Measure.

#### Slice 6.6 — Metadata filters and defaults

**Steps:** filters for document type, policy version effective at a date of service, retired, CED. Make the best configuration the default. Write the before/after table.

**Acceptance (M6):** `docs/retrieval-results.md` shows baseline → hybrid → rerank → contextual numbers.

---

### Milestone 7 — The agent

#### Slice 7.1 — Output models

**Steps:** `Citation` (chunk id, document, page, bbox, quote ≤ ~25 words), `CriterionResult` (criterion id, status, confidence, rationale, citations, branch taken), `CaseRecommendation` (overall status, missing documents, letter draft).

#### Slice 7.2 — Tools, one at a time

**Steps:** implement and unit-test each tool: `search_policy`, `search_case_documents`, `get_conditions`, `get_observations`, `get_medications`, `get_facts`, `check_code_coverage`. Clear docstrings (the model reads them).

#### Slice 7.3 — Evaluate one criterion

**Steps:** Pydantic AI agent that evaluates a single criterion for a case with the tools; Sonnet for the determination. Validate that every "met" has ≥1 citation pointing at a real chunk.

**Acceptance:** correct result on the CPAP AHI criterion for 3 dev cases covering different branches.

#### Slice 7.4 — Case orchestration

**Steps:** loop over the service's verified initial-phase criteria; aggregate into a `CaseRecommendation` with missing-document list; store `criterion_results` and `case_recommendations` with a run id.

#### Slice 7.5 — Model routing and cost

**Steps:** Haiku for query rewriting and extraction, Sonnet for determinations; record tokens and cost per case.

#### Slice 7.6 — Letter of medical necessity

**Steps:** draft from cited evidence only; never invent facts; include citations as footnotes.

#### Slice 7.7 — CLI and traces

**Steps:** `cli.evaluate_case <case_id>` prints a criterion table, recommendation, cost, latency; full Logfire trace per case. Make target `evaluate-case`.

**Acceptance (M7):** any golden case runs end-to-end.

---

### Milestone 8 — End-to-end evals, API, review screen

#### Slice 8.1 — End-to-end evals

**Steps:** `pydantic-evals` dataset from the golden cases; metrics: criterion accuracy, determination accuracy, missing-evidence recall, citation validity (LLM judge — validate it against 20 of the Developer's own labels first), cost and latency per case. Report dev and test splits separately. Make target `eval-cases`.

#### Slice 8.2 — CI eval gate

**Steps:** a small, cheap subset runs in GitHub Actions when `services/coverage_agent/**` changes; fails if accuracy drops below a threshold. API keys as repository secrets.

#### Slice 8.3 — FastAPI

**Steps:** endpoints: list cases, get case with results, trigger evaluation, serve document files, get eval run summaries. Pydantic response models; OpenAPI docs.

#### Slice 8.4 — Review screen (Next.js)

**Steps:** `apps/web`: case list; review screen with criteria checklist (left) and PDF viewer with citation highlights (right) using stored page + bbox; generated TypeScript client from FastAPI's OpenAPI. Persistent "Synthetic data only, not for clinical use" label.

#### Slice 8.5 — README and demo

**Steps:** problem, architecture diagram, how to run, retrieval results table, end-to-end eval results, cost per case, ADR links, limitations ("system evaluation on synthetic data, not clinical validation"), disclaimer ("Independent portfolio project; not affiliated with CMS"). Record a 2–3 minute demo video.

**Acceptance (Phase 1):** Definition of done in section 1 is met.

---

## 6. Progress checklist

- [x] 0.1 Repo skeleton
- [ ] 0.2 Postgres with pgvector
- [ ] 0.3 Python project
- [ ] 0.4 Configuration
- [ ] 0.5 Database layer and migrations
- [ ] 0.6 LLM wrapper, cache, tracing
- [ ] 0.7 CI
- [ ] 1.1 CMS client basics
- [ ] 1.2 License token
- [ ] 1.3 NCD listing
- [ ] 1.4 Fetch respiratory NCDs
- [ ] 1.5 LCDs and articles
- [ ] 1.6 Study the data
- [ ] 2.1 Raw storage and sync loop
- [ ] 2.2 HTML cleaner
- [ ] 2.3 Section splitter
- [ ] 2.4 Policy chunker
- [ ] 2.5 Code tables
- [ ] 2.6 Embeddings and vector storage
- [ ] 2.7 Naive search
- [ ] 3.1 Criterion model
- [ ] 3.2 Extract for one service
- [ ] 3.3 Remaining services
- [ ] 4.1 Generate patients
- [ ] 4.2 HAPI FHIR
- [ ] 4.3 FHIR client
- [ ] 4.4 Case spec and gold labels
- [ ] 4.5 Document generator
- [ ] 4.6 Fax degradation
- [ ] 4.7 Golden set
- [ ] 5.1 Parse one PDF
- [ ] 5.2 Scans and OCR
- [ ] 5.3 Document classification
- [ ] 5.4 Clinical chunker and storage
- [ ] 5.5 Fact extraction (optional)
- [ ] 6.1 Retrieval eval set
- [ ] 6.2 Runner and baseline
- [ ] 6.3 Hybrid search
- [ ] 6.4 Reranking
- [ ] 6.5 Contextual retrieval
- [ ] 6.6 Metadata filters and defaults
- [ ] 7.1 Output models
- [ ] 7.2 Tools
- [ ] 7.3 Evaluate one criterion
- [ ] 7.4 Case orchestration
- [ ] 7.5 Model routing and cost
- [ ] 7.6 Letter draft
- [ ] 7.7 CLI and traces
- [ ] 8.1 End-to-end evals
- [ ] 8.2 CI eval gate
- [ ] 8.3 FastAPI
- [ ] 8.4 Review screen
- [ ] 8.5 README and demo

---

## 7. Guardrails

- **Spend:** spend limits set in the Anthropic and Voyage consoles; Haiku by default; disk caches for LLM and embedding calls; full eval runs only on demand.
- **Data:** synthetic patients only; licensed LCD/article content never committed; ingestion scripts re-download it.
- **Evals:** tune on the dev split only; report the test split.
- **Scope:** new ideas go to `docs/ideas.md`, not into the current slice.
- **ADRs:** write a half-page ADR (context, decision, alternatives) for: pgvector vs a separate vector DB, Docling, Voyage, chunking strategy, hybrid + rerank configuration.
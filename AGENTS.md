# ePA Portal — Agent Context

Read this before touching anything in this repo. It is the live production codebase for
ePayslip's Performance Appraisal portal (WS7 of the Middle Office AI Transformation Programme).
Owner: Wong (HR Manager / MO Pillar Lead). This file is picked up automatically by Qoder
(AGENTS.md compatibility) — keep it current as the project evolves.

## What this is

- **Frontend:** single-file `index.html` (~230KB) — plain HTML/CSS/JS, no build step, no
  framework. Load Chart.js and SheetJS from CDN in `<head>`. This is the deployed artifact.
- **Backend:** Supabase project `rfayekgpmrrzmyxtchzr` — Postgres + Auth + Row Level Security
  + one Edge Function (`pa-notify`, sends email via Brevo).
- **Tables:** `profiles`, `cycles`, `pa_submissions`, `pa_submission_versions`, `audit_log`.
- **Hosting:** GitHub Pages, repo `faith0703/epa-portal`, serves `index.html` at repo root from
  the `main` branch. Live at https://faith0703.github.io/epa-portal/
- **This folder is a normal git clone of that repo.** Deploy = commit + push to `main`.
  GitHub Pages rebuilds automatically (~1 min). No manual upload step, no clipboard paste.
  (Older docs in the parent `WS7_ePA_Portal` folder describe a pbcopy-into-GitHub-web-editor
  process — that was a workaround for *not* having a proper local git clone. It's obsolete now
  that development happens here. See `ePA_Deploy_Runbook.md` for the current process.)

## Non-negotiable rules (Wong's working style — read `../WS7_PA_*` docs for full context if unsure)

- **Never assume business logic.** Scoring formulas, rating bands, RLS policies, CC/GL-style
  mappings — confirm with Wong before changing. Ask one targeted question at a time.
- **Ask before building.** Confirm scope and intended behavior before writing code, especially
  anything touching scoring, payroll export, or auth/RLS.
- **No rework.** Correctness over speed. Read the actual source before claiming something is
  broken or fixed — this codebase has a documented history (see Post-Incident Review below) of
  bugs that looked fixed but weren't, because nobody re-verified against live source.

## Critical history — read before changing scoring, RLS, or the Increment Engine

`../ePA_Post_Incident_Review_v1.1.docx` documents a near-miss in July 2026: a "final score" field
was calculated but never persisted for months; fixing that promoted three latent display bugs
into payroll-corrupting ones. Key lessons baked into the current code:

- **Scoring must be computed by one pure function and persisted, not recalculated ad hoc.**
  `computeFinalScore()` is that function. Manager-view and employee-view element IDs are
  deliberately namespaced (`m_` prefix for manager fields) to prevent state bleeding between
  the two views. Do not let manager review re-read employee-form DOM elements or vice versa.
- **RLS policies must not use bare `using (true)` / `with check (true)`**, and a policy's *name*
  is not proof of its behavior — always read the actual predicate (`pg_policies`) before trusting
  a policy. `migrations/003_v2.3_rls_hardening.sql` has the reference query.
- **The Increment Engine (salary increment %) is intentionally feature-flagged OFF.** There is no
  approved merit matrix — the bands were hardcoded in June 2026 without sign-off from Finance/
  compensation owners. Do not re-enable without an explicit go-ahead from Wong that a real merit
  matrix has been approved. Do not print increment % on any export or PDF while it's off.
- **Any new `innerHTML` interpolation of user-supplied data must go through `esc()` (HTML
  attribute/text context) or `jsq()` (inline `onclick` JS-string + HTML-attribute context,
  in that order).** 124 call sites were retrofitted for this in v2.3 — don't add a 125th
  unescaped one.
- Module-level state (`OBJS`, `SC`, `RVW`) must be fully cleared between reviews / on sign-out —
  partial clearing caused the score-leak bug in v2.4.

## Pre-deploy checklist (still applies even though push replaces clipboard-paste)

1. `python3 -c "print(sum(1 for b in open('index.html','rb').read() if b>127), 'non-ASCII bytes')"`
   — currently the file is kept 100% ASCII (entities/`\u{}` escapes) as a leftover safety habit
   from the old paste-based deploy. Not strictly required now that deploy is via git, but don't
   reintroduce raw multi-byte UTF-8 without checking with Wong first — some tooling downstream
   may still assume ASCII-only.
2. Extract and syntax-check inline `<script>` blocks with `node --check` before pushing.
3. Grep for new `innerHTML =` sites and confirm `esc()`/`jsq()` wrapping.
4. If you touched RLS or schema: the SQL lives in `migrations/*.sql` in this repo but is
   **not applied automatically** — it must be run manually in the Supabase SQL Editor
   (dashboard → project `rfayekgpmrrzmyxtchzr` → SQL Editor). Confirm the verification query
   at the bottom of the migration file returns the expected policies before considering it done.

## Key docs (in parent `WS7_ePA_Portal` folder, not duplicated here)

- `ePA_Portal_CHANGELOG.md` — full version history and why each fix happened
- `ePA_Post_Incident_Review_v1.1.docx` — the incident writeup referenced above
- `ePA_Technical_Specification_v1.3.docx` / `ePA_User_Guide_v1.3.docx` — current-state reference
  docs (kept deliberately separate from incident narrative — see Post-Incident Review Lesson 7)
- `ePA_Deploy_Runbook.md` — deploy process (being updated for the git-based workflow)
- `ePA_Supabase_Setup.md` — first-time Supabase project setup if ever rebuilding from scratch

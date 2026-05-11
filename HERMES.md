# Hermes instructions — face-swap-video

## Mandatory highest-priority skill

Before making any code, test, script, config, or documentation change in this project, Hermes must load and follow the Hermes skill:

```text
context-aware-dev
```

This skill is the canonical Hermes procedure for this project. It requires reading the current project context and CRAG supplemental context, then using `workflow-crag-starter` to locate impact scope before editing.

## Required local context files

Read these first for project work:

1. `context/project-context.md`
2. `context/crag-supplemental-context.md`

Do not use stale root README/HERMES/task notes as the source of truth when the context files contain the relevant fact.

## Cross-agent compatibility

- Codex-compatible instructions are in `AGENTS.md`.
- Hermes-compatible instructions are in this `HERMES.md` plus the `context-aware-dev` skill.
- The detailed CRAG-derived module map is in `context/crag-supplemental-context.md`.
- If one of these instruction entrypoints changes, keep the others semantically in sync.

## Project rules summary

- Flutter Android App only; Android validation has priority.
- Build from `/tmp/zfj/apps/face-swap-video/app` to avoid Chinese-path Gradle/Java issues.
- Background conversion starts only after the app actually enters background, not immediately after clicking generate.
- FaceFusion API base URL: `https://facefusion.baoganai.com`.
- Current API paths: `/api/health`, `/api/swap/image`, `/api/swap/video/job`, `/api/swap/status/{jobId}`, `/api/swap/result/{jobId}`.
- Do not update dashboard/docs site or project overview unless the user explicitly asks.

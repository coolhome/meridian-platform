---
name: exec-narrative
description: >-
  Write or refresh this repository's executive narrative (where we were, where we are, where we
  are going, how it is coming out) from the handoff docs, git history, memory and the live Azure
  Pipelines state, or write an executive assessment of a proposed platform change ("what if we
  did X"). Use it whenever the user asks for an executive summary, a narrative, a status or an
  update for leadership, "how is it going", "where are we", "the story so far", a recap of the
  rollout, or a what-if question about the platform, even when they do not say "executive".
  Every result is stored under docs/executive so the next one starts from the last.
compatibility: >-
  PowerShell 7, Azure CLI with the azure-devops extension signed in to the organization
  (credential-manager mode, no PAT needed), gh CLI. All Azure DevOps access is read-only.
---

# Executive narrative

Two modes. Pick by the shape of the ask.

| Ask sounds like | Mode | Template |
| --- | --- | --- |
| "how is it going", "where are we", "give me the story", "status for leadership", "recap" | **Narrative** | `assets/narrative-template.md` |
| "what if we did X", "should we switch to X", "would X work here" | **Assessment** | `assets/assessment-template.md` |

Both are written for leadership readers who know what a CI/CD platform is but have not followed
the day-to-day. They read one of these to decide something or to brief someone else, so the
verdict comes first, every number is verified, and nothing depends on having watched the work.

## Narrative mode

### 1. Gather evidence before writing a word

The story must be true as of now, not as of the last handoff. Run the independent reads in
parallel; they take a minute and the narrative is only as good as they are.

1. **Previous narrative.** The newest narrative in `docs/executive/` is the baseline: its
   "where we are" becomes this note's "where we were", and the new note says what changed since.
   If there is none, the arc starts at the first commit.
2. **Latest handoff.** `docs/handoff-N.md` with the highest N holds the state table, the ordered
   next steps and the blockers. Treat its attributions of failures as hypotheses, not facts
   (see step 2).
3. **Git history since the previous narrative.** `git log --date=short --format="%h %ad %s"`
   from the previous note's date. Commit messages carry the fix-by-fix story (template tags,
   rounds of first-run findings).
4. **Live pipeline state.** Run `scripts/Get-PipelineState.ps1` from PowerShell. It prints
   hosted-minute usage, the latest runs, and for every failed run the stage and job results plus
   the issues and error log lines of each failing task. `references/azure-devops-evidence.md`
   has the individual commands and the traps for going deeper (variable groups, checks, logs).
5. **GitHub sync workflow.** `gh run list --workflow=sync-to-azure-repos.yml --limit 3` says
   whether mirrors and the bootstrap are flowing.
6. **Memory.** The recalled `meridian-rollout-state` note carries the sandbox facts and what is
   blocked on the user.
7. **Reference feedback log.** `grep -E "^## " docs/reference-feedback.md` gives the size of the
   secondary deliverable. Leadership cares because grading the reference is the point of the
   project.

### 2. Verify every failure to the log line

Do not characterise a failure from its stage name or from the handoff's guess. On 2026-09-19 two
of five failures were attributed to a feed permission; the logs showed one was a feed URL scoped
to the organisation instead of the project, and one was a variable missing from a variable group.
The handoff had been written before the runs finished, which is normal. Read the failing task's
issues and log lines (the script prints them), then confirm the cause in the repo or the
service: grep the template, list the variable group, read the Bicep parameter. Each row of the
status table needs a cause and an owner of the fix, and both must be things you saw.

### 3. Write it

Use `assets/narrative-template.md`. The shape matters because a reader compares notes over time.

* **Header table**: audience, evidence-as-of timestamp, sources, which note it supersedes.
* **Where we were**: the arc so far, compressed. Since the previous note if there is one.
* **Where we are**: what the latest evidence shows. A status table with one row per pipeline or
  workstream: stage reached, cause, owner of the fix. Call out what the last handoff got wrong.
  Name the one genuinely good number if there is one.
* **Where we are going, and how it is coming out**: the ordered path to the next milestone,
  then the backlog after it, then the honest headline followed by the honest reading of it,
  then two or three named risks, then the state of the secondary deliverable.

Style, because leadership skims: lead with the outcome; one idea per sentence; numbers in
tables, not prose; no em-dashes; state the honest headline plainly before interpreting it; say
"the platform owner" rather than "you" so the note reads the same to whoever opens it.

### 4. Store, index, remember

* Save as `docs/executive/YYYY-MM-DD-<slug>.md` (slug like `rollout-narrative`). A second note
  on the same day gets a numeric suffix.
* Add one row to the index table in `docs/executive/README.md`: date, kind, link, one line.
* If the live evidence changed the rollout state, update the `meridian-rollout-state` memory
  so the next session starts from the truth.
* Do not commit unless the user asks; pushes trigger the sync workflow.
* Reply with the narrative itself (the user reads it in chat), preceded by the audience line,
  and the path where it was stored.

## Assessment mode

A what-if is answered the same way a narrative is: evidence first, verdict first.

1. **Pin down the proposal** in one sentence and state it back in the header table, so a
   misread is caught immediately.
2. **Gather the facts that decide it**, in parallel: what the repo already does (grep the
   templates and tooling for the thing being replaced), what the live service says (usage,
   quotas, pools, variable groups; see the reference file), and what Microsoft Learn says today
   (use the Microsoft Learn MCP tools; pricing and support matrices change, so never quote them
   from memory).
3. **Write it** with `assets/assessment-template.md`: verdict in the header; what it is; what
   it buys here, with a table of the numbers that decide it; what it changes and the catches,
   each with its evidence; what it does not do; the decisions that belong to the platform owner;
   a recommendation with a scope.
4. **Store and index** exactly as in narrative mode, slug like `<topic>-assessment`.

The assessment is honest about what it does not fix. A good what-if often lands as "yes, but
after the current milestone", and saying so is more useful than enthusiasm.

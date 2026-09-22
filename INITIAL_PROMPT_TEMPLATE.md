# Initial Prompt Template — Governance-Hardened Reference Platform

This file holds the *opening* prompt for the engagement: the request as it would be
made on day one, before anything exists.

It is deliberately free of design decisions. It says what must be true of the finished
platform, never how many repositories, components, environments or services to create,
what to call them, what language or runtime to use, or which product features to build
beyond the thinnest end-to-end slice. Those are the agent's to decide and defend — the
point of the exercise is to see what a competent agent arrives at from the requirements
alone.

The working conventions under *Working artifacts* are the deliberate exception: they are
prescribed because they are what keeps a multi-session, multi-agent engagement resumable,
and leaving them to chance costs a session every time context is lost.

**How to use it:** replace every `<...>` placeholder, delete this header section, and
paste the rest as the first message of a new session.

---

## The request

Build a greenfield reference platform from nothing: a small `<product: e.g. an approval
workflow — a signed-in user raises a request, an approver clicks Approve>` product,
deliberately shaped like an enterprise system, whose real purpose is to exercise
`<execution plane: e.g. Azure DevOps>` and Git governance as hard as possible.

The product itself stays thin. It exists so that there is something real to build, test,
version, promote and deploy — the governance around it is the deliverable.

## Platform boundaries

* `<source host: e.g. GitHub>` is the source of truth. All development happens there.
* `<execution plane: e.g. Azure DevOps>` is the execution plane: builds, artifacts,
  environments, approvals, deployments. Code reaches it by mirroring, not by being
  authored there.
* `<cloud: e.g. Azure>` hosts the running system.
* The mirror is one-way and automatic. A human should never have to copy code between
  the two hosts.

## The primary source

`<if reference material is supplied:>` `<reference documentation set: e.g.
https://coolhome.github.io/azp-reference/llms.txt, an llms.txt index of the whole set>` is
the primary source for this work. Read the index before designing anything, and pull the
pages it points at before each piece of work rather than once at the start — the pages that
matter when you are designing templates are not the ones that matter when you are writing
bootstrap scripts. Prefer it over vendor documentation and general search; when it runs out
or is wrong, go elsewhere, and record where that happened. Grading it is a deliverable in
its own right — see *The reference feedback log* below.

## What must be enforced, not merely documented

Every one of these is a property of the system that a pipeline run can prove or break.
A rule that lives only in a document does not count.

* **Components are independent.** No component may reference another component's source.
  Anything shared travels as a published, versioned artifact.
* **Only governed pipelines can deploy.** A pipeline that does not inherit the central,
  governance-owned definition cannot reach a shared environment at all.
* **Consumers cannot smuggle arbitrary steps into a governed build.** Extension points,
  if any, are allow-listed and the violation fails early.
* **Promotion is gated, and the gates tighten toward production.** The earliest
  environment may deploy automatically; production must not be reachable by one person
  acting alone.
* **Branch protection is code.** Applied idempotently by tooling from a definition in the
  repository, never clicked into a UI.
* **Governance content distributed into components is drift-checked.** A local edit to
  it fails the build.
* **Version pins are per-consumer.** Rolling a new version of any governed, shared
  definition is an opt-in change in each consumer, never a global flip.

## Cost posture

Target the cheapest credible shape of a real production system: prefer services that
scale to zero or bill per use, the lowest tier that still demonstrates the control, and
short retention. Keep the total under `<budget: e.g. a small fixed monthly figure>` and
state the expected monthly cost, itemised, as part of the design.

## Automation expected

Standing up the platform from an empty `<execution plane>` organisation must be
scriptable end to end: project, teams, repositories, environments, checks and approvals,
artifact feeds, service connections and identities, pipeline definitions, pipeline
permissions and branch policies. Re-running any of it must be safe.

## Working artifacts

This runs over many sessions, and not always with the same agent. The working context
belongs in the repository, not in a chat history:

* **Agent instructions.** A checked-in instruction file at the repository root
  (`CLAUDE.md`, or whatever your agent reads) holding the conventions, the ground rules
  and the map of where things live. Keep it current as the platform grows.
* **Skills.** Any workflow you find yourself repeating by hand gets packaged as a
  checked-in agent skill — its own directory with instructions, templates, reference
  notes and scripts — so the next session runs it the same way rather than reinventing
  it. Recurring work of this kind typically includes gathering live platform state and
  writing status for a non-technical audience.
* **Session handoffs under `docs/`.** Written at the end of a session: what works, what
  is blocked and on whom, the ordered next steps, and any environment constraints
  discovered. The next session should be able to start from verified truth instead of
  re-diagnosing what the last one already learned.
* **Design records.** Where a choice could reasonably have gone another way, record the
  choice and the reasoning next to the thing it governs.
* **The reference feedback log**, below.

Prefer updating these in place over accumulating parallel copies, and keep them honest:
a handoff that overstates what works costs the next session more than it saves.

## The reference feedback log

`<if reference material is supplied:>` Keep a running log under `docs/` of what the primary
source got right, what it missed, and what tripped you up — written as you go, context by
context, not reconstructed at the end. Grading that reference is part of the project's
success, so treat the log as a first-class artifact rather than a byproduct. Note where you
had to consult other documentation, and what you wish had been covered.

## Ground rules

* Decide the decomposition yourself and record the reasoning where a future maintainer
  will find it.
* Verify rather than assume: a control is not in place until a run demonstrates it, and a
  failure is not diagnosed until its log line has been read.
* Where the environment blocks you — permissions, tenant policy, sandboxing — say so
  plainly, note what a human with the right access must do, and keep going on everything
  that is not blocked.

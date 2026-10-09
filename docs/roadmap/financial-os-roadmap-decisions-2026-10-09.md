# Financial OS roadmap decisions: now → December rollover restart (owner, 2026-10-09)

| | |
|---|---|
| Role | The durable record of the owner-approved roadmap decisions of 2026-10-09 (roadmap review accepted, with the owner's changes) |
| Separation | **Separate from the frozen rollover authority.** Rollover stays governed by `docs/rollover-2027-spec.md` v2.1 and resumes from `docs/rollover-december-restart.md` (on branch `rollover-package-d`). Nothing here reopens the rollover |
| Relationship to `canonical-roadmap.md` | That file is stale on sequencing (its 2026-09-13 pointer predates the 2026-10-07 and 2026-10-09 owner rulings). It is **not** edited here; reconciling roadmap and status authority is deferred to the December integration (with `AGENTS.md` law #2 and local `main` `f4ab908`). Where they differ, this record holds the owner decisions of 2026-10-09 |
| Authority | It records decisions; each release still needs its own owner authorization (design → implement → push → acceptance) |

## Sequence (owner-approved)

| # | Item | State / rule |
|---|---|---|
| 0 | **Release 0:** reconciled-week model-edit guard | **CLOSED. Live and accepted 2026-10-09** (`96328a7`; `docs/release-0-reconciled-week-guard.md`) |
| 1 | **Release 1:** trust / Wendy quick wins | **CLOSED. Live and accepted 2026-10-09** (`78ad6c7`, product commits `c4daf1c` + `05d4d3f`; `docs/release-1-trust-quick-wins.md`). Six items: no pre-filled login email; household-safe error/admin wording; typed-date entry in Register filters; truthful Ask Claude credential wording; new-version / reload notice (never auto-reloads; not a replacement for the December stale-client control); FD-3 What-If tab. The Budget "Statement check" item was **dropped** by the owner (see 3.1) |
| 2 | **Release 2:** Register entry assist | **Next. Approved in principle**; needs its own owner authorization (scope in 2.1 below). Before its push, leave one Release 1 tab open: that tab showing the update notice (no auto-reload) is the production proof of the version notice |
| 3 | **R-lite** reconciliation (read-only) | **Conditional.** Decision checkpoint **about Nov 8**: start before rollover only with high confidence that it can be implemented, adversarially tested, used in at least one shadow Saturday, accepted and merged into the rollover branch before the freeze. Otherwise it is the first major build after week 31. Scope in 3.1 below |
| 4 | **Production code freeze** | **Planned Nov 20.** After it, only rollover work and the required December integration. Emergency production correctness or security fixes need an explicit owner decision. Changing the date needs evidence brought to the owner |
| 5 | **December rollover** | Resume from `docs/rollover-december-restart.md`. The December integration reconciles: `origin/main`, the production-work commits, local `main` `f4ab908`, `rollover-package-d`, the parked rollover status, and `AGENTS.md` law #2 |
| 6 | **After rollover** | The remaining Gate R / security / model-authority work, then Gate F (sequence below) |

### 2.1 Release 2 scope (approved in principle)

- "Save & Add Another".
- Preserve date and account context between entries.
- Grouped, searchable categories.
- Payee → category suggestion derived from Register history.
- Possible-duplicate warning.

Rules:
- The Register stays the ledger.
- Suggestions never silently change data.
- Duplicates warn; they never refuse the save.
- No new schema without approval.
- Design within unpinned functions first. Do not assume authorization to re-pin `_renderTxRegister`; if that is genuinely needed, STOP and bring the owner a diff, the alternative and the re-pin impact.

### 3.1 R-lite boundary (v1)

The flow is: institution download → deterministic comparison against the Register → balance tie and unmatched lists → owner adjudication using existing controls.

**Required (owner, 2026-10-09):** R-lite must explicitly address the retirement or replacement of the misleading legacy Budget "Statement check" and its help reference. That item was dropped from Release 1: `renderBudget` is not renamed, retired, edited or re-pinned before R-lite.

Not part of v1:
- no schema;
- no new ledger;
- no reconciliation lock;
- no certification;
- no OCR;
- no bank OAuth.

## Recorded decisions and defects (post-rollover unless stated)

- **F-1 (40% tax-reserve paths).** No new policy decision now. There is no approved 2027 commission-tax reserve policy; never infer 40%. The Tax? mechanism is avoided for 2027-origin commission planning. Implementation is after rollover, unless a current production correctness problem forces escalation.
- **Anthropic credential exposure (security defect).**
  - The key is retrievable by ordinary authenticated household clients: the `goals` read policy is not key-scoped (C1 policy evidence).
  - **Interim owner ruling:** the exposure is accepted **only within the signed-in Adam/Wendy household boundary** until the post-rollover privilege/security work.
  - That work must **remove ordinary client access to the credential**, not merely change wording.
  - Release 1 corrects the false "stored encrypted" claim. That does not fix the defect.
  - If evidence shows exposure beyond the intended signed-in household boundary: **STOP and escalate immediately.**
  - No RLS, schema or grant change before rollover (it would invalidate the C1 and rollover security evidence).
- **Per-device model-action overrides (trust/authority gap).**
  - They are stored only in `localStorage`, so Adam's and Wendy's projections can differ while both screens look valid.
  - Not acceptable as the long-term authority model.
  - Fix after rollover in the Gate R / trust-authority work; do not broaden Releases 1–2 to fix it.
- **GR-1 (server-enforced reconciled-week immutability).** After rollover, together with the explicit owner correction/reopen design. Release 0 covers the ordinary client paths only.
- **Rollover.** **Parked** ("rollover engineering locally prepared through Package F plus Package G rehearsal tooling and C1 production-shape verification; Package E waiting on Q4 owner inputs; T-RB-5 and X-NB5 pending isolated-environment proof; C2 deferred"). This roadmap work must not reopen it.

## After-rollover order (from the accepted roadmap review)

1. Gate R lane:
   - statement checks;
   - certified state;
   - owner Reopen/correction;
   - GR-1;
   - override history;
   - per-device overrides server-side (or removed);
   - data-incomplete banner;
   - H-1;
   - the privilege bundle: TRUNCATE revokes including `app_users`, key-scoped credential access, SRI/CSP.
2. F-1 implementation.
3. Receivables tracker; household follow-ups list; card statement-cycle registry.
4. Owner-editable recurring schedule and settings (designed before the 2028 rollover).
5. Gate F (GF-FC-1 forward-cash walk), then the explicit OWNER HOLD decision.

Later / only if needed:
- import and OAuth (after Edge Functions);
- Ask Claude proxy;
- the 5G-1B ledger;
- What-If rework;
- Calc-Core extraction;
- mobile Register;
- audit-log triggers;
- TX-SPLIT;
- 5G-2 to 5G-5.

## Owner operations (separate from code releases)

- Package B production acceptance.
- Fresh encrypted backup with a recorded SHA.
- Continuity card.
- Begin the household W-4 discussion with Jim.
- Retire the weekly refused-recommendation record **only after verifying** that no accepted runbook or evidence contract requires it.

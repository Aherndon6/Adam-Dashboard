# P3b-1 — Register & Budget Data Integrity: Specification (FROZEN — revision 3.3, 2026-09-18)

**Status:** **FROZEN.** Frozen revision: **3.3** (controlled amendment of revision 3.2). Frozen date: **2026-09-18** (revisions 3–3.2: 2026-09-13).
- Revision 3 was approved for freeze by the owner (Adam) after independent review and committed at `dfbdbb4`.
- Revision 3.1 applies owner rulings arising from the read-only production preflight through the owner-controlled change process (§30); committed at `9824779`.
- Revision 3.2 resolves the §30(a) Week 1 finding by owner decision under the existing Week/Event rule, which adds one budget-line correction to C1 (§30.1).
- Revision 3.3 records the re-based cleanup population and the completed C1/R1 production execution, and splits the application release into A1a → A1b by owner decision (§30.2).
**Authority:** this is the controlling design specification for roadmap phase P3b-1 (including P3b-1.MX). It is subordinate to `AGENTS.md` (Law) and `CODEX_STATUS.md` (State); plan position is `docs/roadmap/canonical-roadmap.md` §3.
**Change control:**
- Any change requires the normal owner-controlled change process: an explicit owner decision, recorded as a new dated revision with a change note.
- Implementation, tests, preflight SQL and execution packages must conform to this document and must not silently diverge from it.
- A contradiction discovered later is raised as OWNER RECONSIDERATION REQUIRED, not resolved in code.
**No execution authority:** freezing authorizes none of the following, each of which requires its own gate (§21, §25, §26):
- implementation or test changes;
- preflight queries or rehearsal;
- SQL execution;
- category, budget-line or transaction data changes;
- schema, RPC, RLS or grant changes;
- production or Supabase contact.
**Revision 2 incorporated:** owner rulings closing OQ-1, OQ-2, OQ-3, OQ-7, OQ-8 and C-8; the legacy `budget_transactions` inclusion trace; the archived/merged, assignability and Goals-consumer rulings.
**Revision 3 incorporates:**
- the explicit legacy key contract (§16.7);
- the registry expense-parent budget-line correction found by that trace (§7, §8, §8.1);
- the `misc.goal_sweep` display-label decision (§12.4, §15.2);
- Wendy's walkthrough reclassified as a post-build operating acceptance gate.
**Revision 3.1 amends (§30):**
- records the production preflight and its resolved confirmations;
- supersedes the Entertainment Event disposition of the August family repayment (it is `misc.extra`);
- refines Week/Event operating semantics;
- fixes the `misc.goal_sweep` line-label population;
- adds the narrow Week/Event budget-line key correction to C1.
**Roles:** Owner and final decision-maker: Adam. Builder / analyst / challenger: Claude Code. Architect review: ChatGPT. Fable remains available as an independent challenger for later gates.
**Plan authority:** `docs/roadmap/canonical-roadmap.md` §3 P3b-1 (incl. P3b-1.MX). **Law:** `AGENTS.md`. **State:** `CODEX_STATUS.md`.
**Repository posture:** balance-free and identifier-free. No dollar amounts, payees, or transaction ids appear here. Row-level evidence (the 51-row cleanup mapping, E0/C6 raw reads, and the approved-exception id list) lives in the owner evidence folder outside this public repository.
**Decision status:** no open owner design decisions. Remaining items are post-build operating acceptance and execution/preflight evidence gates (§29).

---

## 1. Purpose and problem statement

The Register is the source of truth for actual spending and income; Budget reports planned vs actual from it (plus the legacy Budget-entered source). Read-only production evidence (E0, C6; 2026-09-13) and local code review established that the current system allows data states that corrupt or silently misrepresent Budget actuals and planned values:

1. **Uncategorized transactions** — 51 Register rows had no category; uncategorized rows are silently excluded from Budget actuals.
2. **Missing taxonomy** — no honest category exists for bank interest, credit-card payments, generic transfers between household accounts, or Wendy's supplemental BK pay; four intentional reusable Entertainment slots have no live category backing.
3. **Weak save validation** — the Register saves a blank category, and a non-blank category is checked only for `lifecycle_status='active'` against a sign-in-time cache.
4. **Budget representation drift** — the Budget grid comes from a hardcoded registry while countability comes from live categories; budget lines can reference unbacked keys (two slots have active lines today); Manage Lines offers hardcoded keys as "existing categories" without checking.
5. **Silent incompleteness and false values** — monthly actual reads have no completeness proof, no stale-response guard, and load failures are not rendered; legacy rows with unrepresented keys are silently dropped; the Goals living-expense figure silently substitutes hardcoded constants; a failed budget-line reload leaves stale planned values presented as current.

P3b-1 makes normal-workflow data entry honest, makes Budget actuals verified, visibly qualified, or visibly unverified, applies one budget-line validity standard to every financial consumer, and corrects the historical uncategorized population where an honest representation exists.

## 2. Scope and non-scope

### 2.1 In scope
- **Taxonomy (category package):**
  - create four new categories (§12.1);
  - create live backing for the four reusable Entertainment slots `entertainment.event_3`, `event_4`, `event_5`, `week_5` (§12.2);
  - archive four unused legacy entertainment leaves (`entertainment.birthday_dinner`, `entertainment.brunch`, `entertainment.big_dinner_out`, `entertainment.entertainment_other`; zero Register rows in E0-1), metadata preserved;
  - change the live display label of `misc.goal_sweep` and its two active budget-line labels to "Planned for Goals" (§12.4);
  - correct the three Week allowance budget lines stored on Event keys (Week 1 on `entertainment.event_1`, Week 4 on `entertainment.event_4`, Week 5 on `entertainment.event_5`) to their Week keys (§13).
- **Register save validation** (§6) for add and edit through the Register form.
- **Uncategorized visibility:** Register count/filter; Budget COMPLETE WITH UNCATEGORIZED state (§19).
- **Budget representation/exclusion contract** (§7) and invariants INV-A…INV-G (§8).
- **Shared budget-line validity** for all financial consumers, including `_getBudgetLivingExpenses` (§8.1), and the failed-reload correction (§18.3).
- **Manage Lines Add/Edit guard** (§18).
- **Monthly actual source completeness** (§16), **legacy source classification** (§16.7), and **generation-token** protection (§17).
- **Fail-visible Budget and Goals-metric presentation** (§19).
- **Historical NULL cleanup** (§11).
- **P3b-1.MX (Misc/Extra Envelope v1)** wording and Goals metric label (§15). Wendy's walkthrough is a post-build operating acceptance gate (§26).

### 2.2 Explicitly not in scope
- P3c-2 and 2027 rollover.
- TX-SPLIT / split transactions.
- Transfer pairing architecture (`transfer_pair_id` stays dormant).
- Reimbursement-status architecture, a family/shared-reimbursement category, and cross-month reimbursement machinery.
- Server-authoritative action overrides; new reconciliation design; goal-funding architecture.
- runModel, WD/effectiveWD, goal waterfall, reconciliation RPCs, 5F-1 internals.
- Budget identity math.
- **Goals metric formula changes** (C-9 observation only, §15.3) and any Goals-tab redesign beyond §8.1.
- Database `NOT NULL` on `transactions.category_key`; a `budget_line_rules.category_key` FK; changes to `ON DELETE SET NULL` / `ON UPDATE CASCADE`.
- Any schema change, including marker columns.
- Runtime transaction-id allowlists and note-marker conventions.
- **Category key renames.**
- Flipping `FEATURE_FLAGS.useSupabaseRegistries`.
- Month-scoped pagination (§16.5).
- Category-metadata changes to existing categories to express Budget eligibility; lifecycle redesign.
- Changes to the legacy Budget entry form (§16.7.4).
- Payee memory/typeahead and other entry ergonomics (P3b-2 / Wendy Tranche 2).
- General failed-load UX cleanup outside the P3b-1 integrity path; unrelated UI modernization.

## 3. Governing architecture and principles

- **Application-level integrity (conscious choice).** P3b-1 enforces category and Budget integrity in the application and detects violations at runtime and in audits. It does not add server-enforced constraints. See §20.
- **Fail closed / fail visible.** Unverifiable state never renders as a plausible verified value.
- **Source completeness ≠ classification completeness.** Retrieving every row does not by itself prove category actuals are semantically complete.
- **One validity standard per data set.** Every financial consumer of budget lines uses the same validity determination.
- **Honest classification over zero NULLs.** A documented historical exception is preferred to a false category.
- **Category existence ≠ planned amount.** A legitimate reusable slot exists independently of whether a month budgets it.
- **Register ↔ model decoupling is preserved.** Register categories never feed runModel, tax rules, goal state, or reconciliation.
- **Smallest safe change.** No generalized data-access layer; no redesign of the category lifecycle, Budget architecture, or Goals tab.

## 4. Current-state findings (evidence summary)

| # | Finding | Source |
|---|---|---|
| F-1 | 51 NULL-category Register rows, all `source='manual'` (UI-editable). | E0-3, C6 (read-only, 2026-09-13) |
| F-2 | No live category exists for interest income, credit-card payments, generic household transfers, or supplemental BK pay. | E0-1, C6 |
| F-3 | Register save: blank → NULL; non-blank checked only `lifecycle_status==='active'` against `_categoriesCache` (sign-in load). Picker requires active + leaf + assignable. | `index.html` `_saveTxForm`, `_renderTxRegister` |
| F-4 | App write paths to `transactions`: `_saveTxForm` (POST/PATCH incl. `category_key`), `_confirmTxDelete` (DELETE), `_toggleTxCleared` (PATCH `{cleared}` only). No RPC writes transactions. The form never writes `transactions.notes`. | `index.html` |
| F-5 | Budget grid rows/totals come from `BUDGET_CATEGORY_REGISTRY` (32 leaves incl. 10 entertainment slots); Register countability from live categories via `_isCountableBudgetSpend` / `_isCountableBudgetIncome`. | `index.html` |
| F-6 | Income eligibility is not expressible in current metadata: displayed salary income (`income`/`display_only`) and excluded commission income (`commission_income`/`display_only`) are treated identically by the income predicate. | E0-1; `index.html` |
| F-7 | No active countable spend category is missing from the grid; four unused active countable legacy entertainment leaves exist outside the grid. | E0-1, E0-2 |
| F-8 | Registry leaves `entertainment.event_3`, `event_4`, `event_5`, `week_5` have no live category. `event_4`/`event_5` have active budget lines Sep 2026–Jan 2027 (the preflight showed these are Week 4 and Week 5 allowances stored on Event keys, F-25); `event_3`/`week_5` have none. All other 28 registry leaves are backed with metadata matching their row type (local check against E0-1). | E0-1, E0-4 |
| F-9 | Manage Lines Add lists registry leaves under "existing categories only"; `_blrSaveAdd`/`_blrSaveEdit` perform no live-category check. | `index.html` |
| F-10 | `_budgetLoadRegisterSpend` and `_budgetLoadTransactions` issue one GET each with no count/completeness check and no stale-response guard. Neither `'failed'` status has a rendering branch; failures render as empty/zero actuals. Unloaded categories drop all Register actuals silently. | `index.html` |
| F-11 | Both countability predicates require `lifecycle_status='active'`, so Register actuals of archived/merged categories are silently excluded. `chk_leaf_behavior` permits archived/merged rows to have NULL treatment metadata. The app never writes `categories`; lifecycle changes happen only via SQL packages. No `merged_into_key` redirect exists in Budget. | `index.html`; `docs/phase-5d-1-migration.sql` |
| F-12 | Financial amount consumers of `budget_line_rules`: `_getBudgetAmount` (Budget planned), `_getActiveBudgetCategories` (Budget row visibility), `_getBudgetLivingExpenses` (Goals tab). Label-only consumers: `_getCategoryDisplayLabel`, `_getRegisterCategoryLabel`. | `index.html` |
| F-13 | Existing Budget netting: Register inflows in a spend-countable category reduce Spent; income-class inflows count only as income. | `_computeRegisterSpend`, `_computeRegisterIncome` |
| F-14 | RLS: `transactions`, `budget_transactions` and `budget_line_rules` writes allowed for financial writers (owner, household_admin); `categories` insert/update owner-only, delete owner-only and `is_system=false` only. | migration docs |
| F-15 | `_getBudgetLivingExpenses` returns hardcoded fallback constants when budget lines are not loaded, failed, **or loaded with zero rows**, with only a console warning. It sums every active line for the month except `income.*` and `misc.goal_sweep`, with no registry or category check. | `index.html` ~10548 |
| F-16 | `_blrReloadAndRender` (after Manage Lines writes): on a failed reload it retains the prior cache and the `'loaded'` status. | `index.html` ~10889 |
| F-17 | When budget lines are not loaded, `_getBudgetAmount` returns 0 and Budget shows planned `$0` under a warning that "amounts may be estimates". | `index.html` ~9216, ~10581 |
| F-18 | Legacy `budget_transactions` compute semantics — see §16.7.1. Rows with a non-displayed key are silently dropped. | `index.html` ~9309–9431; `docs/phase-5b-budget-schema.sql` |
| F-19 | The legacy Budget entry form is a live second write path (`budget_transactions`). Its category list is the hardcoded registry (non-income, leaf, registry `assignable`); category is required for household expenses in the UI and by DB CHECK. | `index.html` ~9095–9160, ~9648, ~9814 |
| F-20 | Under current derivations, every spend-countable category is also assignable (spend-countable ⊂ assignable). The picker's comment-described "context filtering" is not implemented. The registry's own `assignable` flag is a separate hardcoded value not used for integrity. | `index.html` ~10299, ~10342, ~8665 |
| F-21 | Allocation and Goals wording: registry `misc.goal_sweep` label "Available for Goals"; live category label "Extra Pay Going to Spreadsheet"; Goals card "Available for Goals / Month"; Budget out-of-balance hint "adjust Misc → Available for Goals". | `index.html` ~10526, ~6600, ~9499; E0-1 |
| F-22 | **Registry expense-parent budget line (intentional).** Phase 5E-6 split `entertainment` into ten child slots and ended the parent line at `end_month=2026-06-01`. As of E0-4 (2026-09-13), production had one active budget line on the parent key `entertainment` covering June 2026 (live category active, non-leaf; not a grid leaf). June is a Budget-displayable month (`_budgetAvailableMonths`: Jun 2026–Jan 2027). The Budget legacy rollup adds `_getBudgetAmount(parent.key)` to the group header and Total Planned exactly once each; `_getBudgetLivingExpenses` also includes it. Manage Lines cannot add or edit parent-key lines (Add lists registry leaves; parent header rows have no Edit/Archive controls). | E0-4; `docs/phase-5e-6-migration.sql`; `index.html` ~9396–9406, ~10653 |
| F-24 | **Production preflight (read-only, executed once 2026-09-13).** P3B1-PF (sha256 `2cef8481…`; executed = reviewed) returned 19/19 blocking checks: 17 MATCHES FROZEN EXPECTATION, 2 EXPECTED OWNER CONFIRMATION (PF-09 repayment category, PF-10B `misc.goal_sweep` line labels, both resolved in §14 and §12.4), 0 NON-MATERIAL DRIFT, 0 MATERIAL DRIFT. The 51/49/2 cleanup population was confirmed unchanged. `budget_transactions` = 0 rows; exactly one BACKED_PARENT line. Evidence is preserved outside the repository (§30). | `~/Herndon-Financial-OS-Evidence/p3b-1-preflight-2026-09-13/` |
| F-25 | **Week allowances on Event keys (preflight PF-05B).** The active Sep 2026→open line on `entertainment.event_4` (dated 9/20–9/26, labelled "Entertainment Event 4") is the Week 4 allowance. The active Sep 2026→open line on `entertainment.event_5` (labelled "Entertainment Week 5") is the Week 5 allowance. No active `week_4` or `week_5` line overlaps those months. A third active instance exists: the September-only Week 1 allowance on `entertainment.event_1` (labelled "Entertainment Week 1"). Rev 3.2 adds it to the owner's correction ruling (§30.1). Several open-ended weekly lines also carry September-specific date labels into later months, which is a presentation follow-up (§30). | PF-05B |
| F-23 | **Legacy source volume.** The DR-1 production dump manifest (2026-09-12) records `public.budget_transactions` = 0 rows. No local fixture or evidence shows a legacy row on a parent key or `misc.goal_sweep`. | `~/Herndon-Financial-OS-Evidence/dr-1-restore-rehearsal-2026-09-12/` manifest; `test_regression.js`, `e2e.js` |

## 5. Category data contract

Columns relied on (`categories`): `key` (unique), `label`, `parent_key`, `is_leaf`, `behavior_class`, `budget_treatment`, `cashflow_treatment`, `budget_line_key`, `budget_group_key`, `reimbursement_pairing_key`, `merged_into_key`, `linked_goal_id`, `is_system`, `lifecycle_status ∈ {active, archived, merged}`, `display_order`. Active leaves carry non-null behavior/budget/cashflow (`chk_leaf_behavior`); archived/merged rows may not.

`transactions.category_key` → `categories(key)` `ON UPDATE CASCADE ON DELETE SET NULL`. `budget_line_rules.category_key` and `budget_transactions.category_key` have no FK.

### 5.1 Definitions

These are canonical and shared by the picker, save validation, Budget, Goals and tests.

- **ASSIGNABLE(c):** `lifecycle_status='active' ∧ is_leaf ∧ behavior_class≠'savings_allocation' ∧ budget_treatment≠'planned_allocation'`. Used only for Register entry (picker and save), through one helper.
- **SPEND_COUNTABLE(c):** exactly `_isCountableBudgetSpend(c)` (frozen).
- **INCOME_COUNTABLE(c):** exactly `_isCountableBudgetIncome(c)`.
- **SPEND_COUNTABLE_METADATA(c) / INCOME_COUNTABLE_METADATA(c):** the same tests evaluated with lifecycle ignored.
  - Used only for historical archived/merged classification (§10).
  - Implemented as a minimal wrapper that evaluates the frozen predicate on a copy of the row with `lifecycle_status` treated as active. It must not clone the predicate logic.
  - Parity tests are required (§23).
- **NON_COUNTABLE_METADATA(c):** treatment fields non-null and neither metadata predicate true.
- **INDETERMINATE(c):** `behavior_class` or `budget_treatment` NULL on a leaf.

### 5.2 Current-state relationship (recorded fact, not an architectural coupling)

Under current derivations, SPEND_COUNTABLE(c) ⇒ ASSIGNABLE(c). Invariants do not depend on this. A static test fails if the relationship ever changes, so the change is reviewed deliberately.

## 6. Category assignability and save contract (Register)

**Applies to:** `_saveTxForm` add (POST) and edit (PATCH). **Does not apply to:** `_toggleTxCleared` (payload `{cleared}` only), `_confirmTxDelete`, or the legacy Budget entry form (§16.7.4).

| Case | Required behavior |
|---|---|
| Blank category (new or edit) | Blocked, field-specific message; no request |
| Category passes ASSIGNABLE on a **fresh read at save time** | Write proceeds |
| Archived / merged | Blocked ("That category is no longer active — choose another.") |
| Nonexistent key | Blocked |
| Active but not leaf, or allocation (e.g. `misc.goal_sweep`) | Blocked |
| Fresh read fails (network/auth/non-2xx/unparseable) | Blocked ("Couldn't verify the category — try again."); no write |
| Stale category held in form | Caught by fresh read; blocked |
| Categories unavailable in Register | Visible "Categories unavailable — transactions can't be saved right now" state; save disabled |
| Editing a historical NULL exception | Normal rules apply; no exception-specific code or ids |
| Cleared toggle on any row, including NULL rows | Unaffected |
| Owner and household_admin | Identical behavior |

**Picker:** the blank option becomes a non-selectable "Select a category…" prompt. The existing "(legacy — re-categorize)" display option for a row's inactive current category remains visible but cannot save.
**Fresh read:** one GET for the selected key returning the fields ASSIGNABLE needs; exactly one row satisfying ASSIGNABLE is required.

## 7. Budget representation and exclusion contract

**Representation (single source):** `BUDGET_CATEGORY_REGISTRY` is the authoritative Budget representation. Every registry leaf is intentional taxonomy, including all ten reusable Entertainment slots. Row types:
- **income row:** registry leaf with `isIncome`;
- **planned-allocation row:** `misc.goal_sweep`;
- **expense row:** every other registry leaf.

**Registry expense parent keys** (registry non-income top-level keys with children, e.g. `entertainment`, `misc`) are group-level presentation keys. Their only financial role is the Phase 5E-6 legacy **planned** rollup: a budget line on a parent key contributes to that group's header planned total and to Total Planned, never to a leaf row. Parent keys are **not** valid actual-transaction keys in either source (§10, §16.7). No second list of represented keys is introduced.

**Exclusions (explicit, small):** one code declaration listing only active income-countable categories intentionally **not** represented, each with a reason:

| Key | Class | Reason |
|---|---|---|
| `income.deep_south_commissions` | commission income | Variable commission income handled by the weekly model; not a salary Budget line |
| `business.jabian_deposits_2026` | reimbursable income | Employer reimbursement; must not appear as Budget income |
| `income.interest` | income | Bank interest; not household salary/spending Budget income |
| `income.bkcpa_extra_pay` | income | Supplemental pay handled by the weekly model; not a recurring salary Budget line |

**Rules:**
- A key may not be both represented and excluded.
- The declaration contains no non-income-countable keys.
- Adding a key requires spec/owner approval.

**Proposed shape:** a frozen key → reason object colocated with the registry, consumed only by integrity checks and tests.

## 8. Budget integrity invariants

**BACKED(k)** for a registry leaf key k means a live category with key k exists, is active, is a leaf, and has treatment matching the row type:
- expense row → SPEND_COUNTABLE;
- income row → INCOME_COUNTABLE;
- planned-allocation row → `budget_treatment='planned_allocation'`.

**BACKED_PARENT(p)** for a registry expense parent key p means a live category with key p exists, is active, and is **not** a leaf.

| ID | Invariant | Enforcement |
|---|---|---|
| **INV-A — Registry backing** | Every registry leaf key is BACKED. Every active budget line covering a displayed month uses either a BACKED registry leaf key or a BACKED_PARENT registry expense parent key (the 5E-6 legacy planned rollup, F-22). No unbacked placeholder state exists after the category package. | Runtime at Budget/Goals load (violation → UNVERIFIED / unavailable, naming keys); preflight; static fixture tests |
| **INV-B — Spend coverage** | Every live SPEND_COUNTABLE category is represented as an expense row. Assignability is not part of this invariant (§5.2). | Runtime: an unrepresented spend-countable category → UNVERIFIED if it has transactions in the displayed month, otherwise an audit finding. Preflight: zero unrepresented after the category package archives the four legacy leaves. |
| **INV-C — Income coverage** | Every live INCOME_COUNTABLE category is represented as an income row or listed in the exclusion declaration; represented ∩ excluded = ∅. | Static + runtime |
| **INV-D — Budget-line validity for all financial consumers** | Every financial amount consumer of budget lines (§4 F-12) uses one shared validity determination (§8.1). Invalid or unavailable budget-line state is never treated as a valid financial input. Label-only consumers are exempt. | Runtime; static test that each financial consumer calls the shared determination |
| **INV-E — Manage Lines cannot create an invalid line** | Add offers only BACKED registry leaf keys; Add and Edit refuse to persist any key that is not a BACKED registry leaf (Manage Lines never creates or edits parent-key lines); category or budget-line state unavailable → Add/Edit disabled with a visible message. | e2e (both roles) |
| **INV-F1 — Source completeness** | Each monthly actual source (Register `transactions`, legacy `budget_transactions`) is complete only when the request succeeds, an exact total is available, unique returned-row count equals the total, and the response belongs to the current generation (§16, §17). | Runtime |
| **INV-F2 — Classification completeness** | Retrieved rows are classification-complete only when every row that could affect Budget actuals has a determinable treatment: Register rows per §10, legacy rows per §16.7. Rows with no category are an explicit uncategorized state, never silently complete. | Runtime |
| **INV-G — Honest presentation** | The UI distinguishes VERIFIED, COMPLETE WITH UNCATEGORIZED and UNVERIFIED (§19). None is converted into plausible $0 or silently partial figures. Budget-line-derived Goals values are shown only when budget-line state is valid. | e2e |

### 8.1 Shared budget-line validity determination

`BLR_STATE(monthIso)` is computed from loaded state only (no extra request) and returns one of:

- **UNAVAILABLE** if any of:
  - budget lines not loaded or failed, including a failed reload (§18.3);
  - budget lines loaded with zero rows;
  - live categories not loaded.
- **INVALID** (with keys) if any active budget line covering `monthIso` has a key that is neither a BACKED registry leaf nor a BACKED_PARENT registry expense parent key.
- **VALID** otherwise.

BACKED_PARENT applies **only** to planned budget-line inputs; it never makes a parent key a valid transaction-level actual (§7, §10, §16.7). Parent-key lines contribute exactly as today: group header and Total Planned in Budget, and the `_getBudgetLivingExpenses` sum in Goals. Example: the June 2026 `entertainment` parent line (F-22) is VALID.

**Consumers:**

| Consumer | VALID | INVALID | UNAVAILABLE |
|---|---|---|---|
| `_getBudgetAmount` / Budget grid planned cells (incl. parent rollup) | current behavior | row-level planned for BACKED registry rows remain; **totals derived from budget lines** (Total Planned, total Remaining) show "—"; month UNVERIFIED with keys named | planned cells and totals show "—"; month UNVERIFIED ("Budget lines unavailable") — replaces today's `$0` + "amounts may be estimates" |
| `_getActiveBudgetCategories` (row visibility) | current behavior | current behavior for BACKED rows | falls back to existing zero-row suppression; no amounts shown |
| `_getBudgetLivingExpenses` (Goals) | **current calculation, unchanged** | returns unavailable (no partial sum) | returns unavailable (no fallback constants) |

**Goals rendering** when unavailable:
- "Monthly Living Expenses" and "Planned Monthly Margin (Base Pay)" show "—" with a concise reason ("Budget lines unavailable" / "Budget lines need attention").
- No other Goals-tab element changes.
- The hardcoded fallback constants are no longer returned to any display path.

## 9. Reusable Entertainment slot semantics

The household plans entertainment in two intentionally different ways:

- **Entertainment Week 1–5** (`entertainment.week_1`…`week_5`): reusable weekly entertainment allowance buckets, aligning ordinary entertainment funds to the appropriate week of a Budget month.
- **Entertainment Event 1–5** (`entertainment.event_1`…`event_5`): optional reusable planning buckets for identifiable one-time entertainment events that the household **intentionally plans and budgets separately** (e.g. a special dinner, concert or outing given its own Event allowance). A month may use zero, one, or several Event slots. An Event slot is not a permanent named activity; the same slot may hold different items in different months.
- **Misc / Extra** (`misc.extra`): incidental, miscellaneous or unplanned one-time spending that was not separately planned as an Event.

**Operative distinction (rev 3.1):** a purchase being one-time or entertainment-related does **not** make it an Event. Event applies only when the household deliberately uses a separate Event planning bucket for that item.

**Rules:**
- **Category existence** means the reusable slot is legitimate and available to Budget, Register entry, and Manage Lines.
- **Budget-line existence and amount** determine whether and how much a slot is planned for a particular month. A backed slot with no line or a zero amount for a month is valid and is not an integrity finding.
- Category labels stay generic ("Entertainment Event N" / "Entertainment Week N"). Month-specific names live only in budget-line `line_label` values and must not rename the category.
- There is no "dormant placeholder" state. All ten slots are backed after the category package (INV-A).
- **A Week allowance must use a Week key; an Event key must not carry a Week allowance.** A budget line that does so is a data defect (F-25, §13).

## 10. Archived / merged historical-reference semantics (Register source)

**Local rule of record:** `docs/phase-5c-architecture-design.md` lifecycle table:
- `archived`: hidden from new entry, historical transactions retained as-is;
- `merged`: new entry does not use it, historical transactions remain on the original key.

**Current runtime:** see F-11.

**P3b-1 rule (no lifecycle redesign):**
1. Historical transactions may reference archived or merged categories indefinitely. There is no global rule that referenced categories stay active.
2. Historical Budget treatment follows the **row's own category metadata**. It never silently follows `merged_into_key`; following the target would reclassify history.
3. For the displayed month, each Register row is classified:

   | Row state | Classification |
   |---|---|
   | `category_key` NULL | **uncategorized** (§19 COMPLETE WITH UNCATEGORIZED) |
   | Active **leaf** category | current predicates (counted / not counted) |
   | Active **non-leaf** (parent/group) category — unsupported (save requires leaf); direct-write only | **UNVERIFIED** |
   | Archived or merged, SPEND_ or INCOME_COUNTABLE_METADATA | **UNVERIFIED**: a determinable countable amount the frozen predicate would silently drop |
   | Archived or merged, INDETERMINATE | **UNVERIFIED** |
   | Archived or merged, NON_COUNTABLE_METADATA | no Budget effect |
   | Key absent from loaded category state | **UNVERIFIED** |

4. **Package requirements:**
   - archiving changes `lifecycle_status` only and preserves treatment metadata;
   - a category with references in any Budget-displayable month is not archived or merged without first recategorizing those references;
   - preflight confirms zero references for the four legacy leaves.
5. `_isCountableBudgetSpend` remains byte-identical; classification is implemented around it (§5.1).

## 11. Historical cleanup matrix (52 rows; rev 3.3)

Counts only; the row-level mapping is held in the owner evidence folder and becomes the per-row guard list of the correction package.

| Disposition | Target category | Rows |
|---|---|---|
| Existing category | `income.deep_south_commissions` | 1 |
| Existing category | `taxes.vio_transfer_2026` | 3 |
| Existing category | `transfers.goal_disbursement` | 3 |
| Existing category | `misc.extra` (previously documented as categorized Extra; later found NULL; provenance not investigated) | 1 |
| Existing category | `transfers.goal_funding` (both legs of one savings movement) | 2 |
| Existing category | `income.net_salary` | 2 |
| **Subtotal — existing categories** | | **12** |
| New category | `income.interest` (rev 3.3: +1 row, §30.2) | 12 |
| New category | `transfers.credit_card_payment` (6 opposite-direction pairs) | 12 |
| New category | `transfers.between_accounts` (4 opposite-direction pairs) | 8 |
| New category | `income.bkcpa_extra_pay` (rows dated 2026-07-03, 07-17, 08-14, 08-27, 09-11) | 5 |
| **Subtotal — new-category assignments** | | **37** |
| Owner-approved historical exception | Mixed regular + supplemental payroll deposit (July) — no split, remains NULL | 1 |
| Owner-approved historical exception | Shared auto-parts purchase whose repayment is embedded in aggregated deposits (July) — remains NULL | 1 |
| **Subtotal — approved historical exceptions** | | **2** |
| **Family repayment (rev 3.1)** | August family repayment of an incidental one-time purchase → `misc.extra`, the same existing category as the original purchase (§14). The original purchase is already `misc.extra` and is **not** touched. | **1** |
| **Awaiting architectural disposition** | | **0** |
| **Total** | | **52** |

**Checks and expected effects:**
- **Direction:** 13 outflows / 39 inflows (rev 3.3 re-based population; E0-3 recorded 13 / 38 for the original 51 rows).
- **Rows written by the correction package:** 50 (12 existing + 37 new + 1 family repayment → `misc.extra`). The 2 exceptions and the original purchase are untouched. There is no supplemental transaction write.
- **Expected Budget-visible deltas:**
  - July `misc.extra` actual increases by one row;
  - Net Salary received increases in July and September by one row each;
  - the August `misc.extra` actual is reduced by the repayment, exactly offsetting the original purchase (net zero; existing netting, F-13);
  - all other corrections are Budget-neutral (transfer, excluded, or declared exclusion).
- **After correction:** July and any month containing the two exceptions render COMPLETE WITH UNCATEGORIZED, not VERIFIED.
- **Cross-month limitation (accepted):** a repayment posted in a later Budget month reduces that later month's actual in the original purchase's category; no retroactive rewrite.

**Compatibility finding — Monthly Close v1 (OQ-6 closed):** category-only corrections change `transactions.category_key` and `updated_at` only. They do not change amount, date, cleared state, balances, `weekly_reconciliations`, `goal_funding_snapshots`, month-end balances, or statements, and none is inside the Monthly Close v1 certification basis (`docs/monthly-close-v1-spec-2026-07-14.md` §3.1). **No Monthly Close reopen is required.**

## 12. Category definitions (approved; not created — creation requires C1 authorization, §26)

### 12.1 New categories

| Field | `income.interest` | `income.bkcpa_extra_pay` | `transfers.credit_card_payment` | `transfers.between_accounts` |
|---|---|---|---|---|
| label | Interest Income | **Wendy Extra BK Pay** (exact) | Credit Card Payment | Transfer Between Accounts |
| parent_key | `income` | `income` | `transfers` | `transfers` |
| is_leaf | true | true | true | true |
| lifecycle_status | active | active | active | active |
| behavior_class | `income` | `income` | `transfer` | `transfer` |
| budget_treatment | `display_only` | `display_only` | `excluded` | `excluded` |
| cashflow_treatment | `operating` | `operating` | `excluded` | `excluded` |
| budget_line_key | NULL | NULL | NULL | NULL |
| budget_group_key | `income` | `income` | NULL | NULL |
| reimbursement_pairing_key / merged_into_key / linked_goal_id | NULL | NULL | NULL | NULL |
| is_system | false | false | false | false |
| display_order | 1050 | 1040 | 12040 | 12050 |
| Budget contract | declared exclusion | declared exclusion | non-countable | non-countable |

All four display_order values were unused in E0-1; re-verify at preflight. `commission_income` is intentionally not used for BK pay, and future tax logic must not infer tax treatment from `behavior_class`.

### 12.2 Reusable Entertainment slot backing

These mirror the six existing sibling slots (`event_1`, `event_2`, `week_1`…`week_4`), which are identical in every field except key, label and display_order.

| Field | All four slots |
|---|---|
| parent_key | `entertainment` |
| is_leaf | true |
| behavior_class / budget_treatment / cashflow_treatment | `expense` / `tracked` / `operating` |
| budget_line_key / budget_group_key | `entertainment` / `entertainment` |
| reimbursement_pairing_key / merged_into_key / linked goal | NULL |
| is_system | true |
| lifecycle_status | active |

| Key | Label | display_order |
|---|---|---|
| `entertainment.event_3` | Entertainment Event 3 | 4062 |
| `entertainment.event_4` | Entertainment Event 4 | 4064 |
| `entertainment.event_5` | Entertainment Event 5 | 4066 |
| `entertainment.week_5` | Entertainment Week 5 | 4110 |

Display orders were unused in E0-1 and require no renumbering of existing rows; re-verify at preflight. After creation all ten slots are SPEND_COUNTABLE, ASSIGNABLE, represented, and offered by Manage Lines.

### 12.3 Classification guidance

**Transfer precedence**, highest first:
1. `transfers.goal_funding`
2. `transfers.goal_disbursement`
3. `taxes.vio_transfer_2026`
4. `transfers.greenlight` or another purpose-specific transfer
5. `transfers.credit_card_payment`
6. `transfers.between_accounts` (fallback only)

**Family/shared standalone repayment convention (no category):**
- A standalone repayment tied to a countable original charge uses the original charge's category, so existing netting offsets it.
- This applies to one-time entertainment items as well: the repayment follows the original purchase's category. It is an Event slot only if the original purchase was on a separately planned Event.
- Limitations:
  - cross-month repayments land in the repayment month;
  - aggregated deposits and non-countable originals cannot use the convention;
  - split transactions remain a future capability.

### 12.4 `misc.goal_sweep` display label (owner decision 2026-09-13)

- **Change:** live `categories.label` for `misc.goal_sweep` goes from "Extra Pay Going to Spreadsheet" to **"Planned for Goals"**, in the category package (C1).
- **Display label only.** Unchanged:
  - the key (no rename);
  - `behavior_class` (`savings_allocation`), `budget_treatment` (`planned_allocation`) and `cashflow_treatment`;
  - `is_system` and `lifecycle_status`;
  - assignability (it remains non-assignable);
  - Goals math and goal-funding semantics.
- **Month-specific budget-line labels (resolved rev 3.1, PF-10B):** exactly the **two active** `misc.goal_sweep` lines change to "Planned for Goals": the June 2026 historical line and the Jul 2026→open line. The two inactive lines stay unchanged. Label only; no amount, period, key, treatment or arithmetic change.
- **Code surfaces (A1):** registry label, the Budget out-of-balance hint, and help/hint copy use "Planned for Goals" (§15.2).

## 13. Entertainment slots — CLOSED (owner decisions 2026-09-13; amended rev 3.1)

The ten-slot structure is intentional (§9). The four missing backings are created in the category package (§12.2), as taxonomy completion rather than invariant-driven category creation. The family repayment ruling (§14) does not remove or reduce Event slots.

**Week/Event budget-line key correction (rev 3.1; Week 1 added rev 3.2).** The preflight (F-25) showed three active Week allowances stored on Event keys: the September-only Week 1 line on `event_1`, and the Sep 2026→open `event_4` and `event_5` lines (Week 4, Week 5). These are data defects, not legitimate Event uses. C1 corrects them narrowly:
- Week 1 allowance: key `entertainment.event_1` → `entertainment.week_1`. The label already reads Week 1 and stays.
- Week 4 allowance: key `entertainment.event_4` → `entertainment.week_4`. The label changes only where it misdescribes the role ("Entertainment Event 4 …" → "Entertainment Week 4 …").
- Week 5 allowance: key `entertainment.event_5` → `entertainment.week_5`. The label already reads Week 5 and stays.
- No amount, period, active-flag or Budget arithmetic change. No collision with an active `week_1` (September), `week_4` or `week_5` line. Inactive lines are untouched.
- The correction targets these three known records only. It places no restriction on legitimate, separately planned Event lines on `event_1`–`event_5`.
- Out of scope: other Entertainment history, legitimate Event uses, weekly recurrence architecture, and September-dated labels on open-ended lines (follow-up, §30).

## 14. August family repayment — CLOSED (owner decision 2026-09-13; amended rev 3.1)

**Superseded:** the earlier disposition to an Entertainment Event slot.

**Final ruling:**
- The preflight (PF-09) found the original purchase: an August incidental one-time purchase already categorized `misc.extra`. It was not a separately planned Entertainment Event.
- The original purchase **remains `misc.extra` and is not touched**.
- The family repayment → **`misc.extra`**, the same category as the original, so it offsets exactly (net zero in Misc / Extra).
- It is not income, not a household transfer, and not an Event.
- No person-specific, activity-specific, reimbursement, or recurring category is created. No Event slot is assigned. No cross-month machinery is added.
- The repayment is one of R1's reviewed transaction writes (49 at this ruling; 50 after the rev 3.3 re-base, §30.2). There is no supplemental write.

## 15. P3b-1.MX (Misc/Extra Envelope v1) and Goals metric wording — CLOSED

### 15.1 MX scope (roadmap §3)
- `misc.extra` is the envelope category (namespace-checked against `misc.goal_sweep`, a Do-Not-Touch key).
- A monthly budget-line envelope.
- A month-attribution memo convention ("covered by <month>"), display-only.
- Prior-month carryover as context only.
- One balance-free close attestation line.
- A static test asserting no "Available"/"Free" figure is derived.

Wendy's walkthrough is a **post-build operating acceptance gate** (§26), not a specification or freeze blocker. A material workflow defect found there reopens the relevant behavior through the normal owner process.

### 15.2 Allocation line wording (CLOSED)
**"Planned for Goals"** is the approved name for the `misc.goal_sweep` allocation concept.
- **Code surfaces (A1):** registry label (currently "Available for Goals"), the Budget out-of-balance hint ("adjust Misc → Available for Goals"), the Budget row hint "(flexible sweep line)", and help copy.
- **Live data (C1):** category display label per §12.4; same-concept budget-line `line_label` values per §12.4. No key change (§20).

### 15.3 Goals computed metric
- **Label:** **"Planned Monthly Margin (Base Pay)"**
- **Subtext:** **"Planning estimate — not cash available to move."**
- **Formula (unchanged):**
  - (Adam base net paycheck constant × 2) + (Wendy base net paycheck constant × 2)
  - − (sum of active budget-line amounts covering the calendar month of the current model week's start date, excluding keys starting `income.` and excluding `misc.goal_sweep`)
  - Rounded. Shown only when `BLR_STATE` is VALID (§8.1).
- **Not included:**
  - commissions, extra BK pay, reimbursements, interest, Register actual income;
  - actual spending, account balances, card timing, floor/look-ahead floor, actual goal-funding state.
- **C-9 (observation only):** the base-income assumption uses exactly two paychecks per month rather than biweekly annualization. No P3b-1 formula change is authorized.

## 16. Monthly actual source completeness and legacy classification

### 16.1 Sources
1. **Register actuals:** `transactions` for the displayed month, all accounts (consumed by `_computeRegisterSpend` / `_computeRegisterIncome`).
2. **Legacy actuals:** `budget_transactions` for the displayed month (consumed by the Budget `spentByKey` fold, §16.7).

### 16.2 Request (per source)
One GET with the existing month filter plus `Prefer: count=exact`, selecting the columns already used plus `id`. For Register, `category_key` must be selected (already is). No limit, no pagination.

### 16.3 Verification (INV-F1)
A source is **COMPLETE** only if all of these hold:
- HTTP 2xx;
- the body is an array;
- `Content-Range` parses to an exact non-negative total;
- returned rows = total;
- returned ids are unique;
- the response belongs to the current generation (§17).

Otherwise it is **INCOMPLETE** (count mismatch, missing/malformed count, duplicate ids) or **FAILED** (request error, non-array body).

### 16.4 Server response cap
The API applies a configured maximum rows per response even without `limit`, returning a successful response with fewer rows. Production has demonstrated a cap of at least 421 rows; the exact cap is unknown; current monthly volume is well below it.
- One request plus an exact count **proves completeness when all rows fit within the cap.**
- If returned unique rows ≠ exact total, completeness is not proven and the month **fails closed**.
- The design does not claim to retrieve an arbitrarily large month.

### 16.5 Pagination
Pagination is not required for P3b-1 correctness. It becomes necessary only if a real month legitimately exceeds the cap and that month should remain usable rather than visibly UNVERIFIED. That is a follow-up trigger, not P3b-1 scope.

### 16.6 Helper boundary
One narrowly scoped shared helper for complete month reads of these two sources (request, count parse, verification, generation check). It is not a generalized data-access layer.

### 16.7 Legacy `budget_transactions` classification contract (INV-F2, legacy source)

#### 16.7.1 Current semantics (traced locally)

**Schema** (`docs/phase-5b-budget-schema.sql`):
- `amount > 0`.
- `transaction_type ∈ {household_expense, reimbursable_expense, reimbursement_income}`.
- CHECK:
  - `household_expense ⇒ category_key IS NOT NULL ∧ excluded_from_budget=false`;
  - `reimbursable_expense ⇒ excluded_from_budget=true`;
  - `reimbursement_income ⇒ excluded_from_budget=true ∧ category_key IS NULL`.
- `category_key` is free text with no FK. An empty string satisfies `IS NOT NULL`.

**Load:** `_budgetLoadTransactions` — `select=*`, month date range, ordered; `'failed'` status is not rendered.

**Budget compute** (`index.html` ~9309). A row is added to `spentByKey[category_key]` as `+amount` **iff** all of:
- `transaction_type==='household_expense'`;
- `!excluded_from_budget`;
- `category_key` is truthy.

No live-category, lifecycle, countability, or registry check is applied at fold time.

**Display:** `spentByKey` is read only for:
- (a) registry non-income leaf keys under the rendered expense parents (including `misc.extra` and `misc.goal_sweep`); and
- (b) registry expense parent keys, through the legacy rollup (`spentByKey[parent.key]`, "e.g. 'entertainment' before it was split"). These amounts are also added to the grand total.

Consequences:
- A household-expense row whose key is anything else is **silently dropped**: a non-registry key, an income key, a typo, or an empty string (possible only via direct write).
- `reimbursable_expense` and `reimbursement_income` never affect Budget; they feed only the Budget "Statement check" panel.

**Entry path — new rows** (`_renderBudgetForm` ~9648): the category list is `_getActiveCategoryRegistry()` filtered to `!isIncome && leaf && assignable`, which is the hardcoded registry while `useSupabaseRegistries=false`. This means:
- registry parent/group keys (`leaf:false`) are **not offered**;
- `misc.goal_sweep` (registry `assignable:false`) is **not offered**;
- income leaves are not offered;
- category is required for household expenses (UI `_budgetSubmitForm` and DB CHECK).

**Entry path — editing an existing row** (~9672): if a row's stored key is not in that list, the form renders it as a **selected, savable** "(legacy — re-categorize)" option (Phase 5E-6, written for pre-split `entertainment` rows). Re-saving such a row preserves its key. The UI can therefore **preserve** a parent or `misc.goal_sweep` key on a pre-existing row, but cannot **create** one.

**Rendering of a direct parent-key row** (~9396–9406): `spentByKey[parent]` is added once to that group's header Spent and once to the grand-total Spent (`totalExpSpent`). It is not rendered as a line, not added to any leaf, and not included in the attention strip, so each total counts it once. This is intentional 5E-6 historical support for pre-split `entertainment`, not generic free-text tolerance.

**Rendering of a direct `misc.goal_sweep` row** (~9431–9471): `spentByKey['misc.goal_sweep']` renders as Spent on the "(flexible sweep line)" row, is added to grand-total Spent, and drives that row's over/near state and "Over by" badge.

**Evidence of rows:** none. The production dump (DR-1, 2026-09-12) has 0 `budget_transactions` rows (F-23). No local fixture uses a parent or `misc.goal_sweep` legacy key.

#### 16.7.2 Assessment

| Key form | Supported creation? | Historical rows? | Consistent with P3b-1 semantics? | Ruling |
|---|---|---|---|---|
| Registry expense leaf (not `misc.goal_sweep`) | Yes | 0 legacy rows at DR-1 (2026-09-12) | Yes: same keys as Register expense rows; backing enforced by INV-A | Preserve counting exactly |
| Registry expense parent/group key | No (edit-preserve only) | None | Partly. Planned parent lines are intentional (F-22). A parent-key **actual** cannot be attributed to any leaf and has no Register equivalent (Register blocks non-leaf, §10). | **Fail closed** for actual rows |
| `misc.goal_sweep` | No (edit-preserve only) | None | **No.** It is a `planned_allocation` / `savings_allocation` line that Register never counts as spending. Legacy Spent on it would present an allocation as spending and can raise a false "Over by". | **Fail closed** |
| Blank key | No (UI + DB CHECK; empty string only via direct write) | None | An uncategorized actual | Uncategorized state |
| Unknown / non-represented key (incl. income leaves) | No | None | Unknown category state | Fail closed |

**Conclusion:** the only current behaviors that conflict with P3b-1 semantics (parent-key actuals and `misc.goal_sweep` actuals) have no supported creation path and had no rows at DR-1 (2026-09-12; re-verified at §25 item 8). Failing closed on them changes no counted amount for data known to exist. This is not an owner reconsideration.

#### 16.7.3 Final contract (per legacy row in the displayed month, from a COMPLETE source)

**Legacy expense leaf key** means a registry leaf that is not income and is not `misc.goal_sweep` (i.e. a §7 expense row key).

| # | Row state | Classification | Change from today |
|---|---|---|---|
| L1 | `transaction_type ∈ {reimbursable_expense, reimbursement_income}` | No Budget effect | none |
| L2 | `household_expense` ∧ `excluded_from_budget=true` (DB-prohibited; runtime-tolerant) | No Budget effect | none |
| L3 | `household_expense` ∧ not excluded ∧ key is a **legacy expense leaf key** | Counted exactly as today (+amount to that leaf) | none |
| L4 | `household_expense` ∧ not excluded ∧ key NULL or empty/whitespace | **Uncategorized**: contributes to the §19 COMPLETE WITH UNCATEGORIZED count and net | was silently dropped |
| L5 | `household_expense` ∧ not excluded ∧ key is a **registry expense parent/group key** | **UNVERIFIED**, naming the key ("legacy transaction on a group key") | was counted at group and grand-total level; no rows exist |
| L6 | `household_expense` ∧ not excluded ∧ key is **`misc.goal_sweep`** | **UNVERIFIED**, naming the key ("legacy transaction on the Planned for Goals allocation") | was counted as Spent; no rows exist |
| L7 | `household_expense` ∧ not excluded ∧ any other non-empty key (non-registry, income leaf, typo) | **UNVERIFIED**, naming the key | was silently dropped |
| L8 | unrecognized `transaction_type`, or non-finite amount | **UNVERIFIED** | was dropped / NaN risk |

**Notes:**
- The Budget **planned** parent rollup (parent-key budget lines, §7, §8.1) is retained unchanged. Only parent-key **actual** rows fail closed.
- The actual-side `spentByKey[parent]` rollup code becomes unreachable for counted amounts: L5 prevents parent-key actuals from being verified. Implementation keeps the planned half and must not render a parent-key actual as a verified value.
- L3 counted amounts continue to depend on registry backing through INV-A; an unbacked registry leaf makes the month UNVERIFIED regardless of source.

#### 16.7.4 Legacy entry form
Unchanged in P3b-1. Its category list is the registry (all leaves BACKED after the category package), and category is required by UI and DB CHECK. The edit-preserve "(legacy — re-categorize)" option stays; a preserved parent or `misc.goal_sweep` key is surfaced by L5/L6 rather than silently counted. Direct-write bypasses of the legacy table are covered by L4–L8 and the audit (§20, §27).

## 17. Generation-token / stale-response protocol

- Each Budget actual-load cycle (Budget open, month change via `_budgetChangeMonth`, explicit refresh, post-write reload of either source) increments a Budget generation id, captured for both source reads.
- A response may commit rows, totals, completeness status, or error status **only if** its generation equals the current generation.
- Stale responses are discarded without mutating any Budget state.
- Month-string comparison alone is insufficient (e.g. August → September → August).
- Budget actuals are computed only from a single generation's pair of sources.

## 18. Manage Lines contract

### 18.1 Add
The key list is registry leaves that are BACKED at render time. The label "existing categories" is used only for backed keys.

### 18.2 Add save / Edit save
Before writing, verify with a fresh read that the key is BACKED; otherwise refuse with a visible message and no request. Category or budget-line state unavailable → Add and Edit disabled with a visible message. Existing guards (overlap, entertainment duplicate label, permission) are retained; both roles behave identically.

### 18.3 Post-write reload (C-8, in scope)
If `_blrReloadAndRender`'s reload fails (network error or non-2xx):
- budget-line load status becomes failed;
- `BLR_STATE` becomes UNAVAILABLE for every month;
- Budget planned values and the Goals metrics render unavailable (§8.1);
- a visible message states that budget lines could not be refreshed.

The prior cache may remain in memory but is never authoritative or rendered as valid. A successful reload restores VALID or INVALID per §8.1.

## 19. Presentation contract

### 19.1 Budget actual states (INV-G)

Precedence: **UNVERIFIED > COMPLETE WITH UNCATEGORIZED > VERIFIED**. **LOADING** is shown while the current generation is in flight.

| State | Condition | Rendering |
|---|---|---|
| **VERIFIED** | Both sources COMPLETE for the current generation (INV-F1); every relevant row classification-complete (INV-F2); no INV-A/B/C runtime violation (§8); `BLR_STATE` VALID | Normal |
| **COMPLETE WITH UNCATEGORIZED** | Sources COMPLETE; no UNVERIFIED condition; one or more rows uncategorized (Register NULL-category rows; legacy L4 rows) | Categorized actuals remain visible. Uncategorized rows are not allocated to any category. Notice: "N uncategorized transactions (net $X) are not included in any category's actuals." with a link/filter into Register. Must not be described as verified or fully classified. |
| **UNVERIFIED** | Any source INCOMPLETE/FAILED/stale; categories not loaded; `BLR_STATE` INVALID or UNAVAILABLE; INV-A/B/C runtime violation (§8); unknown category key; archived/merged countable or indeterminate reference (§10); legacy L5–L8; Register active non-leaf reference (§10) | Actual cells and actual-derived totals and strips show "—" with "can't verify". Planned amounts follow §8.1. One integrity message names the reason(s) and suggests refresh. |

**Uncategorized net amount:** signed in the Register convention. Each Register row contributes `amount`; each legacy L4 row contributes `−amount`. N counts rows from both sources.

**Runtime does not distinguish** approved historical exceptions from actionable NULL rows. There are no transaction-id allowlists, no note markers, and no schema changes. That distinction belongs to the recurring audit (§27).

### 19.2 Register
- An uncategorized count and filter.
- A categories-unavailable cannot-save state (§6).

### 19.3 Goals
Per §8.1: "—" with a reason when `BLR_STATE` is not VALID. The label and subtext follow §15.3.

Final copy follows existing UI conventions and is reviewed in the post-build Wendy walkthrough (§26 gate 7).

## 20. Residual-risk statement

Application-level validation does **not** prevent every invalid database state. The following can bypass the normal UI contract:
- direct authenticated REST writes by a financial writer (to `transactions`, `budget_transactions`, or `budget_line_rules`);
- owner SQL/packages;
- permitted owner category lifecycle operations, including a category delete that sets referencing `transactions.category_key` to NULL, and a key update that cascades to transactions but not to budget lines, legacy rows, or the registry.

P3b-1 makes such violations harder through normal workflows, fail-visible when they affect Budget or Goals integrity, and detectable through recurring audits. It consciously does not make them impossible through `NOT NULL`, additional foreign keys, or server authority. This is an accepted residual risk for this two-user household system.

**Operating rules:**
- **No category key renames in P3b-1.**
- Retire referenced categories by archive only, never delete.
- Archive preserves treatment metadata.
- Do not archive a registry-backed category (INV-A would fail visible).

## 21. Migration / execution dependency graph

**Nodes**
- **P0** Spec freeze — **complete** (revision 3, 2026-09-13).
- **P1** Preflight read (reviewed exact SQL; §25) — **complete** (executed once, read-only, 2026-09-13; F-24).
- **C1** Category package:
  - create the four new categories (§12.1) and the four Entertainment slot backings (§12.2);
  - archive the four unused legacy leaves (metadata preserved);
  - change the live `misc.goal_sweep` display label and its two active budget-line labels to "Planned for Goals" (§12.4);
  - correct the Week 1 / Week 4 / Week 5 allowance lines from Event keys to Week keys (§13).
- **R1** Historical correction package: exactly 50 transaction writes (12 existing + 37 new + 1 family repayment → `misc.extra`; rev 3.3, §30.2).
- **A1** Application release: §6, §7–§10, §16–§19 (incl. §16.7, §8.1, §18.3), uncategorized visibility, and §15 wording. MX workflow pieces may ship as their own slice; Wendy's walkthrough is a post-build operating acceptance gate (§26). **Rev 3.3:** A1 is delivered as two sequential releases, A1a then A1b. This is a sequencing split, not a reduction of the A1 contract. Elsewhere in this spec, "A1" means the whole application release, which is complete only when A1b is complete.
  - **A1a** (entry integrity and honest planning display):
    - §6 in full: category required on every normal Register save; fresh single-key read at save time; one shared ASSIGNABLE definition; picker prompt; categories-unavailable cannot-save state.
    - §19.2 uncategorized count and filter, for the selected account only, derived from the complete P0 ledger, without changing `_filterTxRows`. Not presented as household-wide Budget completeness.
    - The §8.1 UNAVAILABLE condition for the Goals consumer: hardcoded fallback values are removed and Goals shows "—" with a reason. The condition is implemented once, as the primitive that becomes the UNAVAILABLE branch of `BLR_STATE` in A1b.
    - §18.3: a failed post-write reload cannot leave the prior cache represented as valid, and the failure is visible.
    - The §17 generation guard on both Budget month reads (no Budget arithmetic change).
    - A visible notice when the current month's actual load fails. Budget values are not replaced, and the wording implies neither completeness nor verification.
    - §15 wording.
    - A1a introduces none of the states VERIFIED, COMPLETE WITH UNCATEGORIZED or UNVERIFIED, and does not imply that Budget totals are complete.
  - **A1b** (integrity certification): every remaining A1 requirement, including:
    - §16 exact-count completeness and unique-id validation;
    - §10 classification and §16.7 legacy L1–L8;
    - §7 exclusion declaration and INV-A/B/C runtime enforcement;
    - the complete `BLR_STATE`, including INVALID, for every financial consumer;
    - §18.1–18.2 Manage Lines backed-key enforcement;
    - §19.1 three-state presentation with the signed uncategorized notice;
    - the §5.2 static guard;
    - fail-closed rendering of actual and planned values.
    - A1b extends A1a; it does not replace or undo it.
- **V1** Post-execution audit (§27).

**Hard dependencies**
- R1 requires C1: the four new non-Entertainment target categories must exist (transaction FK).
- The Week 5 line key correction runs after `entertainment.week_5` is created, in the same C1 transaction. `budget_line_rules` has no FK, but INV-A semantics require the backing.
- A1 (A1a and A1b) requires C1: without slot backing, INV-A renders every month UNVERIFIED, and required-category entry needs honest categories available.
- A1 requires INV-F1, INV-F2 and the generation token in the same release to claim VERIFIED. Under rev 3.3 that release is A1b. The generation guard may ship earlier in A1a, but A1a makes no VERIFIED claim.
- A1b requires A1a.
- V1 requires A1b and the post-build walkthrough (§26 gate 7). **A1a completion does not satisfy any dependency on A1 being complete.**
- C1 and R1 require P1 with no drift, and a passing rehearsal (§26).
- Everything requires P0.

**Not a hard dependency:** R1 ↔ A1 (A1a or A1b). Historical NULL rows render COMPLETE WITH UNCATEGORIZED, not UNVERIFIED.

**Controlling order (rev 3.3):** C1 → R1 → A1a → A1b → full Wendy walkthrough (§26 gate 7) → V1. The release is then audited against corrected data, and data and code roll back independently. A1b completion closes the application-release obligation formerly represented by the single A1 node.

## 22. Rollback boundaries

| Unit | Rollback | Precondition / note |
|---|---|---|
| C1 new categories (`is_system=false`) | Delete the rows | Only while zero references (before R1 or after R1 rollback) |
| C1 slot backings (`is_system=true`) | Owner-approved SQL removal (the delete policy excludes `is_system=true`) | Zero transaction references required. Removing backing re-breaks INV-A, so A1 (A1b, then A1a) must be rolled back first or concurrently. |
| C1 archive | Restore `lifecycle_status='active'` | Before-image; metadata preserved by package rule |
| C1 `misc.goal_sweep` label and two active `line_label` changes | Restore prior labels from before-image | Display-only; no other field changes |
| C1 Week/Event line key corrections | Restore prior `category_key` and label from before-image, guarded by post-image | Must run before any removal of the `week_5` backing |
| R1 | Restore each row's prior `category_key` (NULL) by id from before-image, guarded by current value = post-image | Package-level all-or-nothing |
| A1a, A1b | Revert each release commit (A1b before A1a); redeploy; verify served asset hash | No data coupling; C1/R1 data remains valid under the prior app |

## 23. Acceptance-test matrix

### Save / assignability (static + isolated e2e, owner and household_admin)
- Blank category blocked, with no request.
- Archived, merged, nonexistent, non-leaf and allocation categories blocked.
- Fresh-read failure blocked.
- Stale form category blocked.
- An ASSIGNABLE category → POST/PATCH carries the key.
- Picker and save call the same ASSIGNABLE helper.
- Editing a NULL row requires a category.
- Cleared toggle on a NULL-category row succeeds with payload `{cleared}` only.
- Categories unavailable in Register → visible cannot-save state.
- The legacy retired-category option displays and cannot save.
- Static guard: SPEND_COUNTABLE ⇒ ASSIGNABLE (§5.2).

### Representation / invariants
- **INV-A:** an unbacked registry leaf → UNVERIFIED, naming the key. An active budget line on a non-registry key → `BLR_STATE` INVALID. All ten Entertainment slots backed with no lines → no finding.
- **Parent-key budget line:** a June fixture with an active `entertainment` parent line and a BACKED_PARENT live category → `BLR_STATE` VALID. Group header planned and Total Planned identical to today; `_getBudgetLivingExpenses` identical to today. The existing rollup static test (~7115) keeps its planned assertion. A parent line whose live category is missing, archived, or a leaf → INVALID.
- **Register non-leaf reference** (§10): a displayed-month Register row on an active non-leaf category → UNVERIFIED.
- **INV-B:** an unrepresented spend-countable category with displayed-month transactions → UNVERIFIED; without transactions → no runtime state change.
- **INV-C:** exclusion keys produce no warning; removing one → flagged; represented ∩ excluded → static failure.
- **Frozen predicate parity:** for active categories, the metadata wrapper equals `_isCountableBudgetSpend` / `_isCountableBudgetIncome` across a fixture set covering every behavior_class × budget_treatment combination. The frozen predicate's source hash is unchanged.
- **§10:**
  - archived countable reference → UNVERIFIED;
  - merged reference evaluates the row's own metadata, not the target (fixture where the target is countable and the source is non-countable → no effect; the reverse → UNVERIFIED);
  - indeterminate metadata → UNVERIFIED;
  - non-countable → no effect;
  - unknown key → UNVERIFIED.
- Existing clean fixtures: Budget totals byte-identical.

### Budget-line validity (§8.1, §18.3)
- **VALID:** Budget planned and `_getBudgetLivingExpenses` values identical to today.
- **INVALID:** Budget budget-line-derived totals "—", valid rows' planned visible, keys named; Goals Living Expenses and Planned Monthly Margin "—".
- **UNAVAILABLE**, for each of not loaded, failed, loaded-empty and categories not loaded: Budget planned cells "—" (no `$0`), Goals "—", fallback constants never returned.
- Static test: every financial consumer calls the shared determination; label consumers exempt.
- **C-8:** a Manage Lines save succeeds and the reload fails → status failed, Budget and Goals unavailable with message, the prior cache never renders as valid; a subsequent successful reload restores it (static + e2e).

### Manage Lines (e2e, both roles)
- Add lists only BACKED keys (all ten slots after C1).
- Add/Edit of an unbacked key refused, with no request.
- Category or budget-line state unavailable → Add/Edit disabled.
- Existing overlap, duplicate-label and permission guards pass.

### Completeness, classification and generation (static + e2e)
- **Each source:**
  - rows = total → COMPLETE;
  - rows < total (cap) → UNVERIFIED;
  - missing/malformed Content-Range → UNVERIFIED;
  - HTTP 500 / non-array → UNVERIFIED;
  - duplicate id → UNVERIFIED.
- One source incomplete → UNVERIFIED.
- **Legacy L1–L8:** each case has a fixture.
  - L3 amounts are identical to today for registry expense leaves.
  - L4 contributes to the uncategorized count and net with the correct sign.
  - L5 (parent key) → UNVERIFIED naming the key; the group header and grand total never show that amount as verified.
  - L6 (`misc.goal_sweep`) → UNVERIFIED; no "Over by" state from a legacy actual.
  - L7 → UNVERIFIED naming the key.
  - L8 → UNVERIFIED.
  - Edit-preserve: opening an existing parent-key legacy row in the form still shows the "(legacy — re-categorize)" option (existing test at ~7153 kept).
- **Register uncategorized:** NULL rows (inflow and outflow) → COMPLETE WITH UNCATEGORIZED; the notice shows N and signed net; categorized actuals unchanged; the state is never labelled verified.
- **Precedence:** uncategorized + an incomplete source → UNVERIFIED.
- **Generation race:** August → September → August with a delayed first-August response (success, failure and incomplete variants) → discarded; current state unaffected.
- **UNVERIFIED rendering:** actual cells unavailable (not $0), message visible.

### Goals wording
- Label "Planned Monthly Margin (Base Pay)" and subtext present.
- "Available for Goals / Month" absent.
- Registry `misc.goal_sweep` label and the Budget out-of-balance hint read "Planned for Goals"; "Available for Goals" absent from Budget copy.
- `misc.goal_sweep` remains non-assignable, and its key and treatment are unchanged (static).
- Formula result identical to today under VALID fixtures.

### Historical cleanup (post-execution audit reads)
- NULL rows = exactly the 2 approved exception ids (evidence list); actionable NULL = 0.
- `income.bkcpa_extra_pay` = exactly 5 rows on the five dates.
- `income.interest` = 12 (rev 3.3, §30.2).
- `transfers.credit_card_payment` = 12 (6 opposite pairs).
- `transfers.between_accounts` = 8 (4 opposite pairs).
- The 12 existing-category corrections exact.
- The family repayment on `misc.extra`; the original purchase unchanged.
- Budget deltas limited to §11 expectations.
- Week/Event line correction: the three known Week allowance records are on `week_1` / `week_4` / `week_5` with unchanged amounts and periods. All other budget lines, including inactive historical lines, are untouched. Legitimate Event lines are not restricted. Entertainment group planned totals and Goals living expenses are identical before and after C1.

### Family repayment convention
- An inflow in a SPEND_COUNTABLE category reduces that month's Spent by its amount.
- An inflow in an income/transfer/excluded category does not affect Spent.
- A cross-month repayment affects the repayment month.

### Regression / protected surfaces
- P0 Register ledger tests unchanged and passing.
- Existing BUD, RG, LEDGER, WR, A7 and Manage Lines tests pass after repairs by intent (§24).
- Frozen hashes unchanged: `runModel`, `computeGoalTransferNetting`, `resolveWeekTransfers`, `_computeLedgerBalances`, `_applyDisplayOrderBalances`, `_sortTxRows`, `_filterTxRows`, `_isCountableBudgetSpend`.
- Goal snapshot, closeout and reconciliation tests unchanged.
- Isolated e2e: zero production contact, zero unowned writes, readiness fallbacks 0.

### Adversarial
- Injected category key via form state → blocked.
- Direct REST PATCH to NULL → not blocked; month shows COMPLETE WITH UNCATEGORIZED; audit flags actionable NULL.
- Category delete → NULL → same as above.
- Orphan budget line inserted directly → `BLR_STATE` INVALID; Budget and Goals unavailable.
- Key rename (cascades to Register transactions only) → INV-A / `BLR_STATE` INVALID; legacy rows keep the old key → L7.
- Direct legacy row with unrepresented key → UNVERIFIED.

## 24. Test repairs by intent

| Test | Classification | Repair |
|---|---|---|
| e2e WR-6c, WR-8, WR-9, WR-16, WR2-5, WR2-8, P0-E4 | A — obsolete uncategorized save | Provide a valid category; preserve each test's original assertion (WR-8 additionally asserts `category_key` in POST body) |
| static `test_regression.js` (~8296) pin of "— No category —" (`index.html` ~8670) | A | Assert non-selectable "Select a category…" prompt |
| static `5B-4` (fallback constants when not loaded) and the fallback portion of `5B-21` | A — pins a false-value fallback | Assert unavailable (no constants) |
| static tests that load `_budgetLineRulesCache` without category state (e.g. `5B-5`, `5B-16`; 7 static sites set the loaded status; e2e fixtures reference the cache) | A — fixture lacks state now required | Supply backed category fixtures; preserve the sums asserted |
| static legacy-option tests ("(legacy — re-categorize)") | B — keep | Unchanged; add assertion that save of that key is blocked |
| Tests referencing "Available for Goals" or "Extra Pay Going to Spreadsheet" (registry label, balance hint, fixtures), if any | A | Assert "Planned for Goals" (§12.4, §15.2) |
| Rollup static test (~7115) asserting `spentByKey[parent.key]` | A — actual half now fail-closed (L5) | Keep the `_getBudgetAmount(parent.key)` assertion; replace the actual-rollup assertion with L5 behavior |
| New tests from §23 (C-1 cleared toggle on NULL, C-2 categories unavailable, C-3 generation race, C-8 reload failure, L1–L8, June parent-line validity, `misc.goal_sweep` label, parity, three-state) | C — missing requirements | Added |

Repairs require owner approval at implementation time; the exact list is finalized from the implementation diff.

## 25. Preflight evidence requirements (read-only; exact SQL reviewed before execution)

1. **51 NULL rows unchanged since C6** (id, date, amount, account, category NULL, `updated_at`). Any drift stops execution and triggers re-planning.
2. **Category inventory unchanged since E0-1** for all keys touched. Target keys (four new, four slots) do not exist. Proposed display_order values (1040, 1050, 12040, 12050, 4062, 4064, 4066, 4110) are unused.
3. **Every registry leaf** except the four slots is BACKED with matching treatment (re-confirms F-8). A mismatch stops execution and triggers spec review.
4. **Four legacy entertainment leaves:** zero transaction references, zero `budget_transactions` references, zero budget lines. Current metadata recorded as before-image.
5. **Active budget lines** for every Budget-displayable month: every key is a registry leaf that is BACKED (after C1), or a BACKED_PARENT registry expense parent key (item 11).
6. **Active SPEND_COUNTABLE categories not represented:** expected zero after the C1 archive.
7. **Transactions in Budget-displayable months referencing archived/merged/unknown categories** (§10 input).
8. **`budget_transactions` per Budget-displayable month:** total row count (DR-1 recorded 0 on 2026-09-12) and counts by L1–L8 classification. Any L5 (parent key), L6 (`misc.goal_sweep`), L7 or L8 row stops execution and triggers spec review before release, because those rows would render UNVERIFIED.
9. **August family repayment category (resolved rev 3.1):** the original purchase was found on `misc.extra` (PF-09). The repayment → `misc.extra`, and the original is not touched (§14).
10. **`misc.goal_sweep` labels (resolved rev 3.1):** the two active same-concept lines change; the two inactive lines are unchanged (PF-10B, §12.4).
11. **Registry expense-parent budget lines:** every active line on a registry expense parent key and its covered months. Expected: exactly the June 2026 `entertainment` line (F-22). Any other parent-key line is listed for owner review before release; it is VALID under §8.1 but must be a known historical line.
12. **Register rows on non-leaf categories** in Budget-displayable months (§10). Expected 0.

Raw outputs are preserved outside the repository with exact SQL, timestamps and hashes.

**Execution record (rev 3.1):** the preflight covering items 1–12 was executed once, read-only, on 2026-09-13 with no production mutation. Result per F-24. Package guards use its preserved before-images; each package re-asserts its exact pre-state at execution time.

## 26. Production execution gates

1. Owner approval of this spec (P0) — **satisfied** by the 2026-09-13 freeze of revision 3.
2. Owner approval of each exact preflight and package SQL text.
3. **Rehearsal requirement (mechanism not fixed).** Before production execution of C1 and R1, the exact guarded package is rehearsed against a sufficiently production-representative disposable dataset such that:
   - target rows exist with the expected pre-state;
   - success assertions execute;
   - mismatch/abort behavior is exercised;
   - production is untouched;
   - rehearsal residue is disposable.

   Candidate mechanisms: a local/disposable database, a Supabase preview branch, or another safe environment. Each needs separate owner approval. No environment creation or paid service is authorized by this spec.
4. Owner authorization per production package execution (C1, R1), each with in-transaction assertions and preserved evidence.
5. Implementation review plus static/e2e acceptance evidence for A1, separately for each of A1a and A1b (rev 3.3); owner commit authorization; owner push/deploy authorization; served-asset hash verification; read-only production smoke.
6. Deployment timing avoids the Saturday cash-certification sitting.
7. **Post-build operating acceptance (Wendy walkthrough).** After implementation of A1b (the full walkthrough follows A1b, rev 3.3) and staging/isolated validation, Wendy walks through Register entry, Budget states, Manage Lines, and the Planned for Goals / Planned Monthly Margin wording. Acceptance is required before MX workflow pieces are treated as operational. A material workflow defect reopens the relevant behavior through the normal owner process. This gate does not block specification freeze.

## 27. Post-execution and recurring audit

- **NULL-category Register rows**, split by the owner evidence id list held outside the repository into approved historical exceptions (expected exactly 2) and actionable NULL defects (expected 0). This split is audit-only; runtime does not perform it.
- **Legacy `budget_transactions`:** total rows, and L4–L8 counts (expected 0 unless owner-dispositioned).
- **Per-category row counts** for §11 targets; opposite-direction pair checks for card payments and between-account transfers; the family repayment on `misc.extra`; the Week 1 / Week 4 / Week 5 allowance records on Week keys.
- **INV-A…INV-D** clean against production data (all 32 registry leaves backed; no invalid active budget lines); exclusion declaration consistent with live categories.
- **Budget spot checks** for July, August and September:
  - expected state — July COMPLETE WITH UNCATEGORIZED (the two exceptions), others VERIFIED unless evidence shows otherwise;
  - deltas match §11;
  - no other actual changes.
- **Goals:** Living Expenses and Planned Monthly Margin identical to pre-release values when budget-line state is VALID.
- **Register P0 counts** unchanged for representative accounts.
- Evidence preserved outside the repository; balance-free summary recorded in State.

## 28. Protected / frozen surfaces

- runModel internals; WD / effectiveWD; goal waterfall ordering and `ira_cpa_cleared` gate; 5F-1 Cash Availability Engine internals; reconciliation RPCs and state machine; `computeGoalTransferNetting`, `resolveWeekTransfers`.
- Budget identity math before 5G-3 (no counted amount changes for any supported row state; legacy parent-key and `misc.goal_sweep` actuals fail closed instead of counting, and none existed at DR-1 per F-23); the `misc.goal_sweep` key.
- `_isCountableBudgetSpend` (byte-identical), with wrapper and parity tests only.
- The Goals metric formula (label, subtext and availability only).
- Register transaction schema; `budget_transactions` schema; `cash_commitments` schema; no fake Register transactions.
- P0 Register ledger loader and balance helpers (`_loadTxLedger`, `_computeLedgerBalances`, `_applyDisplayOrderBalances`, `_sortTxRows`, `_filterTxRows`).
- RLS role model; `anthropic_key` guardrail; production DDL (none planned); golden masters.
- Monthly Close v1 architecture (compatibility finding only, §11).
- The legacy Budget entry form.
- `index.html` script body growth limited to in-place changes on existing Register/Budget/Goals surfaces per the 2026-09-13 in-place ruling.

## 29. Decision register and remaining items

**Closed owner decisions (2026-09-13):**
- OQ-1: ten-slot Entertainment taxonomy.
- OQ-2: family repayment → `misc.extra` (rev 3.1; supersedes the Entertainment Event offset).
- OQ-3: "Planned for Goals"; "Planned Monthly Margin (Base Pay)" plus subtext.
- OQ-4: code-declared exclusions.
- OQ-5: completeness guard.
- OQ-6: no Monthly Close reopen.
- OQ-7: budget-line validity applies to all financial consumers.
- OQ-8: audit-only exception distinction.
- C-8: reload failure is fail-visible and in scope.
- Archived/merged rule.
- INV-B uses spend-countability.
- Frozen predicate wrapper.
- Rehearsal as a requirement.
- No key renames.
- `misc.goal_sweep` display label "Planned for Goals" in C1 (display only).
- Wendy walkthrough is a post-build operating acceptance gate.
- Legacy key contract L1–L8 (parent-key and `misc.goal_sweep` actuals fail closed; planned parent rollup retained).
- Week/Event semantics (rev 3.1): Event only for separately planned items; incidental one-time spending may be `misc.extra`; Week allowances must use Week keys.
- PF-10B (rev 3.1): two active `misc.goal_sweep` lines → "Planned for Goals"; inactive unchanged.
- Week 4 / Week 5 allowance line key correction in C1 (rev 3.1); Week 1 added (rev 3.2).

**Freeze record:** revision 3 frozen 2026-09-13 by owner approval (`dfbdbb4`); revision 3.1 controlled amendment 2026-09-13 (`9824779`, §30); revision 3.2 controlled amendment 2026-09-13 (§30.1).

**True owner design decisions remaining:** none.

**Post-build / business acceptance gates:**
- Wendy's operating walkthrough (§26 gate 7), including final UI copy.

**Execution/preflight evidence gates:**
- The §25 preflight is complete (F-24).
- Remaining: owner approval of exact C1/R1 package SQL, the §26 rehearsal, and per-package production authorizations.

---

## 30. Revision 3.1 amendment record (owner-controlled change, 2026-09-13)

**Trigger:** read-only production preflight P3B1-PF.
- Executed once, 2026-09-13T21:07Z, project `usayoldrawwmjsmretin`.
- Executed SQL sha256 `2cef8481e58fa47e90ac73e22894dfa5202e9fc8dc136eeb6e6bde21083b9ed5` (= reviewed).
- Raw result sha256 `7dbc7c97862b6a6b1e05aa9aef3714e0e3392ce35146d671a6015b04dd0f43f2`.
- Evidence folder: `~/Herndon-Financial-OS-Evidence/p3b-1-preflight-2026-09-13/`.
- No production mutation.

**Result:** 19/19 blocking checks; 17 MATCHES FROZEN EXPECTATION; 2 EXPECTED OWNER CONFIRMATION, both resolved; 0 NON-MATERIAL DRIFT; 0 MATERIAL DRIFT.

**Amendments:**
1. **Cleanup population confirmed:** 51 NULL rows; 49 receive categories; 2 approved exceptions remain NULL.
2. **PF-09 resolved:** the original August purchase stays `misc.extra`; the family repayment → `misc.extra`; no Event slot; no supplemental R1 write; R1 = 49 (§11, §14). Earlier Event-slot wording is superseded throughout.
3. **Entertainment operating semantics refined (§9):** Week = reusable weekly allowance; Event = optional, separately planned one-time allowance; incidental one-time spending does not automatically become Event.
4. **PF-10B resolved:** the live `misc.goal_sweep` category label and its two active budget-line labels → "Planned for Goals"; inactive lines unchanged; display only (§12.4).
5. **Week/Event line defect:** Week allowances must use Week keys. The Week 4 and Week 5 allowance lines on `event_4` / `event_5` are corrected to `week_4` / `week_5` in C1, with only the label change needed for truthfulness. No Budget arithmetic change (§13).
6. **Ten-slot Entertainment taxonomy unchanged:** `event_3`, `event_4`, `event_5` and `week_5` backings are still created (§12.2).
7. **Calendar hold superseded:** the prior Sep 26 calendar-only production hold is superseded by owner ruling. Execution is gate-based; Cal 38 remains protected, and any gate failure stops work (State: `CODEX_STATUS.md`).

**Open findings recorded, not decided here:**
- **(a)** The September-only Week 1 allowance on `entertainment.event_1` (active) is the same defect class as amendment 5. **Resolved in rev 3.2 (§30.1):** corrected in C1.
- **(b)** Open-ended weekly lines (`week_2`, `week_3`, and the corrected Week 4 / Week 5 lines; the corrected Week 1 line is September-only) carry September-specific date ranges into October–January. Presentation/data-hygiene follow-up only.
- **(c)** Inactive Event-key lines labelled Week 1 / Week 5 are not loaded by the application and are left unchanged.

## 30.1 Revision 3.2 amendment record (owner-controlled change, 2026-09-13)

**Trigger:** owner decision on the §30(a) finding after package review.

**Amendment:** the active September-only Week 1 allowance stored on `entertainment.event_1` is corrected to `entertainment.week_1` in C1.
- Label unchanged; it already reads Week 1.
- Amount, period, active flag and Budget arithmetic unchanged.
- The preserved preflight evidence shows no active `week_1` line covering September 2026.

**Unchanged:**
- the Rev 3.1 Week/Event rule (applied, not altered);
- the ten-slot taxonomy;
- R1 (49 writes);
- inactive historical Event-key lines (untouched);
- open-ended September date wording (follow-up, not P3b-1 scope).

C1 grows from 17 to 18 row mutations. No other contract change.

---

## 30.2 Revision 3.3 amendment record (owner-controlled change, 2026-09-18)

**Triggers:**
- the 2026-09-17 production-state re-base of the C1/R1 execution runbook (rev 2.7.3, CHG-15);
- the completed C1/R1 production execution under runbook rev 2.7.4 (closed COMPLETE 2026-09-18; balance-free record in `CODEX_STATUS.md`);
- the owner decision of 2026-09-18 to deliver A1 as A1a → A1b.

**Amendment 1: re-based cleanup population (counts only).**
- Ordinary household activity on 2026-09-17 added one legitimate uncategorized Register row. Its correct category, `income.interest`, did not exist until C1 created it. CHG-15 reviewed and added it as the 50th R1 target.
- The authoritative successor population is **52** rows: **50** R1 targets and **2** approved exceptions. It breaks down as 12 existing-category corrections, **37** new-category assignments (`income.interest` 11 → **12**) and 1 family repayment. Direction: **13** outflows and **39** inflows.
- R1 was executed with exactly 50 writes, and its postcheck passed.
- §11, §14, §21 and §23 are corrected to these counts. No contract, category, target category or Budget expectation changes: the added row is a declared exclusion (§7) with no Budget-visible effect.
- Row-level detail stays in the owner evidence folder (`p3b-1-rev273-rebase-2026-09-17/` and the sealed sitting RUN). No household amount, payee or transaction identifier enters this repository.
- **Preserved as historical truth** (dated or provenance statements, not current assertions):
  - §1 and F-1 (51 rows at E0/C6);
  - F-24 and §25 item 1 (the 2026-09-13 preflight population);
  - the header's "51-row cleanup mapping";
  - §21 P1 ("executed once, 2026-09-13"; later sittings re-ran a re-based preflight under the execution runbook);
  - §29 "Remaining" execution gates (since satisfied: packages approved, rehearsed, authorized and executed);
  - the §30 and §30.1 amendment records.

**Amendment 2: A1 delivered as A1a → A1b (§21).**
- A sequencing split, not a reduction of the P3b-1 contract. A1b remains an explicit P3b-1 obligation.
- A1a addresses demonstrated operating risks without claiming that Budget totals are verified:
  - new uncategorized saves;
  - stale or invalid category saves;
  - saves while category authority is unavailable;
  - fabricated Goals values from fallback constants;
  - stale Goals values after a failed budget-line reload;
  - Budget month-switch response races;
  - silent actual-load failures;
  - inconsistent wording.
- A1b is the integrity-certification layer and earns the stronger claim.
- The split is accepted because A1a is an independently honest intermediate state that A1b extends rather than undoes. It does not rest on any claim that A1b's failure conditions cannot occur.
- **V1 remains blocked until A1b is complete.** Controlling order: C1 → R1 → A1a → A1b → full Wendy walkthrough → V1.

**Unchanged:** every other section, including the §23 acceptance matrix and the §24 test repairs (both still apply, allocated between A1a and A1b per §21), and all protected surfaces (§28).

---

*FROZEN — revision 3.3, 2026-09-18 (revisions 3–3.2: 2026-09-13). Balance-free and identifier-free. Changes only through the owner-controlled change process.*

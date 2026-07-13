> **Advisory source review — not implementation authority.** Superseded for sequencing decisions by:
> - `docs/post-5g-1d-canonical-roadmap-synthesis-2026-07-13.md`
> - `docs/post-5g-1d-roadmap-amendment-calc-core-extraction-2026-07-13.md`
>
> Retained for provenance and architectural detail.

---

Architecture Review — Application Structure of the Herndon Financial OS
Scope: index.html modularity, calc-core extraction sufficiency, roadmap placement. Review only — nothing implemented, nothing committed.
Grounding: direct inspection of index.html (10,074 lines), test_regression.js, e2e.js, fixtures/runmodel-golden-pre-1c-2.json, git history, AGENTS.md, CODEX_STATUS.md, docs/post-5g-1d-canonical-roadmap-synthesis-2026-07-13.md, and the three 2026-07-12 reviews.
1. Executive verdict
Your instinct is directionally right and the cure is already mostly on your roadmap. index.html is a material and rising maintainability and change-safety risk — but the risk is not "10,000 lines" as such. It concentrates in three specific couplings:
The frozen calculation core keeps accreting inside the file by freeze exception (5G-1A.5, 5G-1C-1, C3 overlay, 5G-1C-2.1 Leg 1, 5G-1D Slice 1, and Slice 3 is about to land there too). Every exception is individually controlled; collectively they are the strongest evidence that extraction is late, not early.
The test suite pins implementation shape, not just behavior. ~337 of ~1,461 static tests assert against index.html source text, and the other ~1,073 behavioral tests run through a harness that evals the single inline <script> block — so any structural move breaks tests today, which quietly taxes every future change and grows the migration debt with each new source-pattern test.
The engine's inputs and outputs flow through ~15 mutable globals, with at least one demonstrably fragile pattern (scenario preview mutates global overrideData with no try/finally — index.html:9197).
The planned calc-core extraction (canonical P6, re-slotted legacy 5G-2.5) is the right and sufficient structural move — provided its charter is widened by four thin riders (shared-utility module, engine input adapter, window-bridge + e2e-over-HTTP infrastructure, and the already-mandated test migration). A distinct broad application-modularization phase should NOT be added to the roadmap now. The view layer, Register, Budget, and reconciliation UI should stay in index.html through the 2027 rollover, with broad modernization remaining the deferred, merged 5L/5I-4 label the roadmap review already recommended.
2. Current architecture risk assessment
Hard evidence
Churn concentration: 168 of 239 commits since June 1 (70%) modify index.html. Every feature, hotfix, and freeze exception is a semantic merge through one file.
One classic script: lines 858–10,072 are a single non-module <script> (~9,215 lines JS): ~326 top-level functions and ~130 top-level vars, all implicitly window-global. CSS is lines 8–781; the HTML shell (74 lines, lines 784–857) is genuinely minimal — the mount-point architecture is already clean.
DOM-pinned globals: 147 inline onclick= attributes in generated HTML plus 14 explicit window.*= assignments require handler functions to stay resolvable at global scope (index.html:7737 even has a banner admitting this).
Data access is diffuse: 58 raw fetch(SUPA_URL+'/rest/v1/...') call sites across 18 endpoints, each hand-assembling headers/Prefer; supabase-js is used for auth only (index.html:7925). A window.fetch monkey-patch implements the staging write-block (index.html:7890).
Render architecture: renderApp() (index.html:7790) recomputes the full model and re-renders the active section via innerHTML; 168 call sites invoke it after every mutation. This immediate-mode pattern is conceptually clean and performs fine at this data size — it is not the problem.
Global-state hazards in the calc path: runModel reads reconData, goalSnapData, commitmentData, taskData, overrideData, budgetRules, actionOverrides, goalFlags, registries, and ~20 constants, and writes the global ruleAudit. getActiveModel() temporarily swaps overrideData[wn] to run scenario previews and restores it only on the success path.
Accretion artifacts: dead code retained in-file (_DEAD_renderRoadmap_phase2, ~85 lines at index.html:5358); duplicate escapers esc()/_esc(); year-pins hardcoded in getCurrentWeek/getWeekStartDate/WD/PLAN_YEAR (the rollover surface).
Test coupling (the decisive constraint)
The static harness reads index.html, regex-extracts the inline script, rewrites const→var, and evals the whole app with DOM/fetch stubs (test_regression.js:21–42). On top of that:
Mechanism	Count	Breaks on verbatim move?
Behavioral calls into eval'd functions (M1)	~1,073 tests	Yes today — but fully recoverable by teaching the loader to concatenate module files into the eval'd source
Raw source-text greps of index.html (assertIncludes(html,…), htmlSrc.includes, block regexes)	~294 tests	Yes — must be migrated or repointed per moved function; no loader change saves them
fn.toString() greps of live functions	33 tests	Survive a move (function still exists) unless the moved source text changes
String-slice of function bodies (renderBudget, Register render region, _saveTxForm) + 2 new Function recompiles (_parseTxAmount, _isValidTxDate)	16 tests	Yes if those specific functions move — all currently in clusters I recommend not moving
e2e (Playwright)	129 tests	Behavior-driven and mostly safe, but e2e defaults to file:// (e2e.js:50) — browsers refuse ES modules under file://, and e2e + inline onclick reach window._budgetToggleCleared, window._budgetDeleteTransaction, window.getAuthHeaders by name
The golden master (fixtures/runmodel-golden-pre-1c-2.json) is a value pin, not a byte pin: it re-derives runModel(7000, 7694.87) at pinned currentW=5 and deep-compares weeks/goalCompletion/getGoalFunded. This survives extraction unchanged — it is exactly the right instrument.
Net risk statement: the app is not fragile at runtime — the push gate (full static + e2e before every push), the golden master, the freeze rules, and the phase discipline are real, functioning mitigations. The risk is economic and compounding: each structural move costs test migration; each deferred month adds source-pattern tests and freeze exceptions to the pile; the single file serializes all work and makes the blast radius of any edit the whole app. Left alone, this is the difference between a system one person can safely modify in 2029 and one nobody can (the roadmap review's own words).
Classification of the areas you asked about
Area	Location (lines)	Size	Character	Verdict
Bootstrap	10058–10072 + initAuth/checkAuthorization 7922–8071	~165	Auth-first state machine → loadAll() → renderApp()	Keep in place; boot call moves to the module entry at extraction
Global state	~130 vars, clustered 917–1330, 5714–5747, 8229–8243	—	Domain caches + UI state + staging state, all window-global	Becomes the explicit input contract of the calc module; UI state stays
Data access	58 fetch sites spread through features; getAuthHeaders; staging patch	—	Raw PostgREST, hand-rolled headers	Seam is real; isolate for new code now (js/data/api.js at 5G-2), migrate legacy opportunistically — no big-bang
Calc engine / weekly model	runModel 2206–2670 + reconEffectiveWD 2188 + budget-rules engine 9002–9131 + AMEX lookahead/5F-1 engine 1661–1750 + goal registry 1537–1660 + constants/WD 859–916	~1,300	The frozen core; pure-ish, globals-fed	Extract (calc-core phase) — this is the planned P6 work
Register logic	5710–6976	~1,267	State + ledger sort/filter/balance math + CRUD writes + renders; Wendy-critical, weekly polish cadence	Keep together in-file; pure ledger helpers (_computeLedgerBalances, _sortTxRows, _filterTxRows) are extract-ready if ever needed, but not now
Budget logic	6977–7789 + category registry/BLR 8250–9001	~1,570	Renders + CRUD + BLR admin modal + shared category resolution	Keep together; note: Budget identity math is Do-Not-Touch until after extraction anyway
Reconciliation workflow	Payload builders/gates 1751–2205 (pure-ish) + UI actions 2701–2877 + form renders/setters 3840–4131	~780	Builders already take explicit args; UI is DOM-coupled; 5G-1D Slice 3 lands here imminently	Freeze until 5G-1D is fully done, then builders move to calc-core as a late slice; UI stays
Goal-funding logic	Waterfall inside runModel; getGoalFunded/_latestGoalSnapshot 4548–4578; funding renders 4642–5355; buildCloseoutSnapshotRows 2827–2877	~850	Engine-side (frozen) vs view-side (labels, _fundingWhenLabel already pure)	Engine side extracts with calc-core; view side stays
Cash-planning logic	Does not exist yet in app code (no showCashPlanning; 5G-1/5G-2 app-side unbuilt)	0	Mandated to ship as ES modules	Build as modules from day one — this is where the module skeleton gets proven
Rendering	renderApp 7790 + section renderers 3305–5688 + Chart.js flight path	~3,900	innerHTML template builders; immediate-mode	Keep in place — highest DOM coupling, lowest payoff, actively evolving
Modal/nav/events	setSection, edit drawer, scenario/BLR/category-report modals, 147 inline onclicks	~700	Global-name-resolved handlers	Keep; formalize as an explicit window-bridge list at extraction
Shared utilities	r/f/fc/fsigned/esc 2671–2700, date/week helpers 8246–8248 + 9010–9053, _dollarsToCents, validators	~120	Pure, zero DOM	Extract first — cheapest slice, needed by calc-core anyway
Test coupling	See table above	—	Shape-pinned + harness-coupled	Migration plan is already a canonical hard dep of extraction; honor it
3. Recommended target boundaries
Target end-state for 2026 (vanilla JS, GitHub Pages, no framework, no build step — ES modules load natively; the only workflow cost is a local static server, which is already standing law for 5G code):
index.html                     — CSS, HTML shell, ALL view/render code, UI state,
                                 event handlers, auth UI, loadAll orchestration
js/app.js                      — single <script type="module"> entry: imports calc/lib,
                                 assigns the explicit window bridge, calls boot
js/lib/money.js                — r, f, fc, fsigned, fSpent, _dollarsToCents, _parseTxAmount
js/lib/dates.js                — getCalWeek, getCurrentWeek(clock-injectable), week/monthIso
                                 helpers, addMonthsToDateStr, pinnedMonthlyDateStr, isValidISODate
js/lib/esc.js                  — one escaper (retire the esc/_esc duplicate)
js/calc/constants.js           — OP_FL, MIN_XFR, lookahead depth, seed thresholds, PLAN_YEAR,
                                 starting balances (the rollover's per-year config point)
js/calc/inputs.js              — buildModelInputs(): the ONE place globals are read;
                                 scenario preview passes an overridden input set instead of
                                 mutating overrideData
js/calc/goals-registry.js      — mapGoalFromDB, validateLoadedGoals, waterfall arrays
js/calc/budget-rules.js        — validateBudgetRule, generateOccurrenceDates,
                                 buildBudgetRuleContext, applyBudgetRulesForWeek, dateToModelWeek
js/calc/availability.js        — 5F-1 engine + amxSweepKeepsFloor/maxSafeAmxSweep/isReservedAsOf
                                 (move-only; internals stay frozen)
js/calc/engine.js              — runModel(inputs) → {weeks, ruleAudit}; reconEffectiveWD;
                                 the four seams (eligible set / capacity / allocation policy /
                                 decision emission) reified per the AR review
js/calc/recon-payloads.js      — phase 1/2/3 builders + completeness gates (post-5G-1D only)
js/calc/closeout.js            — buildCloseoutSnapshotRows + snapshot eligibility
js/data/api.js                 — getAuthHeaders + fetch wrapper + staging write-block;
                                 used by all NEW code from 5G-2 onward
js/features/<5g-x>/…           — new features per the existing data/domain/view standing rule
Globals that become explicit interfaces:
The model-input set (reconData, goalSnapData, commitmentData, taskData, overrideData, budgetRules, actionOverrides, goalFlags, GOALS_REGISTRY, goalFundedAmounts, WD) — gathered by buildModelInputs(), never read directly by calc modules.
ruleAudit — becomes a return value; a global alias is kept for the view until tests migrate.
The window bridge — a single documented list in js/app.js of every name inline onclick and e2e reach for (Object.assign(window, {...})). This converts "everything is accidentally global" into "these ~150 names are deliberately global."
Role/flags (USER_ROLE, canWriteFinancials, FEATURE_FLAGS) and Supabase config — passed or imported explicitly by new modules; legacy view keeps reading globals.
Circular-dependency risks found (and their resolutions):
runModel → aoW/aoLabel/aoDeleted → actionOverrides (UI-editable localStorage state read inside the engine). Resolution: overrides become part of buildModelInputs().
Scenario system ↔ overrideData (preview-by-global-mutation). Resolution: input-level override in inputs.js; add a characterization test for the preview path first.
Register ↔ Budget share _categoriesCache/_budgetLineRulesCache/_budgetCatByKey (index.html:6552, index.html:8418), and Budget reads Register's transactions for spend. Resolution: none needed now; if either is ever extracted, a shared categories.js must come out first or you mint a cycle.
getGoalFunded (view) reads global currentW + GOALS_REGISTRY + goalSnapData + vm — keep it view-side; the golden master already pins it.
resolveWeekTransfers (5G-1B history resolver, index.html:2914) spans engine output, taskData, and the write path — classify as a domain adapter; it moves only after 5G-1B settles its final shape.
DOM couplings that make extraction difficult (leave them where they are): saveRecon's gv(id) reads form inputs straight from document.getElementById (index.html:2751); saveWeekEdits/_readEditEvents parse the edit drawer DOM; Chart.js canvas lifecycle in initFlightPathChart; document.body.style.overflow modal management; the 147 inline onclicks. None of these block calc-core extraction because the pure builders behind them already take explicit arguments.
4. Incremental extraction sequence
Slice 0 is infrastructure; slices 1–5 are the calc-core phase proper. Each slice = one commit, full static + e2e + golden-master green, zero behavior diffs.
#	Slice	Current responsibilities	Module boundary	Dependencies	Required tests	Risk	Belongs to
0a	e2e over HTTP	e2e defaults to file://, which cannot load ES modules	Static-server mode in e2e runner (or HFOS_URL default to a local server)	None — do with 5G-2 infra	Full e2e parity run file:// vs http before any module ships	Low	5G-2 hard dep (already listed in canonical P5)
0b	Harness repoint	test harness evals only the inline script	Loader concatenates js/**/*.js module sources (imports/exports stripped or shimmed) into the eval'd source	None	Meta-test: loader finds N module files; suite count unchanged	Low	Extraction precondition
0c	Golden-master expansion	One zero-snapshot fixture	Add current-behavior fixtures: seeded snapshots, overrides active, budget rules active, commitments present	Adam approval (protected fixtures)	New fixtures captured pre-move, held byte-stable through every slice	Low	Extraction gate (already a canonical hard dep)
0d	Target-architecture doc	Module posture is "de facto hybrid, nowhere stated" (RM §2.2)	One page declaring the Section-3 boundaries + window-bridge contract	None	n/a	None	Extraction plan gate (satisfies the 5I-4 declaration)
1	js/lib/* + window bridge + boot move	Money/date/format/escape utils; boot call at script tail	lib/money.js, lib/dates.js, lib/esc.js; js/app.js entry calls boot	0a–0b	Golden master; migrate the handful of source-text tests naming these helpers	Low	Calc-core extraction
2	js/calc/budget-rules.js + goals-registry.js	Occurrence generation, rule context, registry mapping/validation	Pure functions, explicit args (already true)	Slice 1	Existing behavioral tests repointed by 0b; WC-3 disposition unchanged	Low	Calc-core extraction
3	js/calc/availability.js	5F-1 engine + AMEX lookahead	Move-only; internals remain frozen per Do-Not-Touch	Slice 1	5F-1 behavioral suite (heavily tested: isReservedAsOf 29 call sites, getCashAvailabilityEngine 10)	Low-medium	Calc-core extraction
4	js/calc/engine.js + inputs.js + constants.js	runModel, reconEffectiveWD, waterfall, engine block; global reads	runModel(inputs)→{weeks, ruleAudit}; adapter reads globals in one place; scenario preview becomes input override	Slices 1–3; runModel freeze exception = "move-only under golden-master identity" (already authorized by AGENTS.md wording)	All golden masters value-identical; PHASE-A Week-27 byte pins; scenario-preview characterization test added before the move	Medium — the one genuinely delicate slice	Calc-core extraction
5	js/calc/recon-payloads.js + closeout.js	Phase 1/2/3 builders, completeness gates, snapshot payload builder	Pure builders (signatures already explicit)	After 5G-1D activation + Slice 7 + repairs — Slice 3 is about to modify this exact region	Existing builder suites (buildPhase2NewCommitments 15 call sites, buildCloseoutSnapshotRows 18)	Low-medium	Calc-core extraction, final slice
6	js/data/api.js	58 scattered fetch sites	Headers + wrapper + staging guard; new code only; legacy sites migrate opportunistically when their feature is next touched	0a	Contract tests per endpoint as sites migrate	Low per-site; high if big-banged — don't	Standing rule at 5G-2, not a phase
Explicitly not in the sequence: Register, Budget, reconciliation UI, renderers, modals, nav, auth UI, wishlist, Ask Claude.
5. Roadmap placement
The canonical synthesis already slots extraction correctly; code inspection confirms it. Relative order:
5G-1B (holding→payout) and 5G-1E — before extraction, unblocked by it. 5G-1B is calendar-forced (RCCL divergence clock ~Cal Wk 30, inside the Alaska freeze; DCL before Wk 41) and touches runModel — it lands as the last in-body freeze exception under golden master. Do not block it on modularization. 5G-1E is RPC/DB-side and independent.
Monthly Close v1 — independent, no ordering constraint. It is file-based certification with zero code (OM's design). Do not couple it to modularization in either direction.
5G-2 Planned Outflows — before extraction, and it carries slice 0a. 5G-2 is the first real ES-module feature; its hard deps already include the ES-module + static-server workflow. Standing that infrastructure up (plus the harness repoint 0b and js/data/api.js) as part of 5G-2 means extraction inherits a proven module pipeline instead of pioneering one.
Calc-core extraction — immediately after 5G-2, before 5G-4a, before any Budget-identity change, before rollover implementation. Practically ~Sep–Oct 2026 given the freeze (Jul 24–Aug 10) and the P3 activation/repair work.
5G-3 Cash Allocation — keep the standing rule: extraction first. Strictly, a purely derived read-side 5G-3 wouldn't need it, but the 5G-3 spec must define its relationship to the 5F-1 engine; if that relationship needs engine-side change, extraction-first is mandatory, and keeping the existing AGENTS.md rule avoids re-litigating the freeze boundary. If schedule pressure demands, 5G-3 spec work can proceed in parallel with extraction slices.
5G-4a/4b/5G-5 — strictly after extraction. They are the consumers of the testable waterfall API; this is the critical path the canonical doc names ("extraction is the pinch point").
2027 rollover (hard deadline 2027-01-09) — after extraction. The rollover needs js/calc/constants.js as its per-year config point plus the schema/RPC year-pin work; doing rollover against the un-extracted in-body engine means one more round of hand surgery on a frozen core under a hard deadline. Extraction is what makes the rollover a bounded change.
Broader view-layer modularization — post-rollover, 2027 backlog. Keep it as the merged 5L/5I-4 "architecture modernization" label per the RM recommendation ("extraction now; modernization plan later; one label"), pulled only by a concrete forcing function.
6. Explicit non-goals
No framework, no bundler, no build step, no TypeScript, no replatform — ES modules load natively; nothing found in this review justifies a build step.
No view-layer rewrite: renderApp + innerHTML immediate-mode stays; no virtual DOM, no component system.
No event-delegation conversion of the 147 inline onclicks — the explicit window bridge makes them a documented contract instead.
No Register/Budget/recon-UI extraction in 2026.
No big-bang migration of the 58 legacy fetch sites.
No CSS/HTML splitting (cosmetic churn; also interacts with the BUILD_TS pre-commit stamp).
No behavior changes under the extraction flag, ever: skip-vs-break, floors, waterfall order, ira_cpa_cleared, WD/effectiveWD, Budget identity math all move verbatim; design changes wait for their own phases (5G-3+/5G-4) per the Do-Not-Touch list.
No editing golden-master expectations to make anything pass (standing law).
7. Do now / do later / do not do
Action	When	Why
DO NOW (docs/standing rules only, while 5G-1D finishes)		
Adopt a standing rule: new static tests assert behavior (call functions), not source text, wherever feasible	Now	Stops growing the ~337-test migration pile at zero cost
Write the one-page target-architecture/module-posture doc (0d)	Now	Already owed (RM §2.2 / 5I-4); makes every later slice mechanical
Charter the extraction phase with slices 0–5 + the riders in §4	Now (paper)	Converts a "floating gate" into a scoped phase with acceptance gates
DO LATER (sequenced)		
e2e HTTP mode + harness module-concat + js/data/api.js (slices 0a/0b, new-code rule)	With 5G-2	5G-2's own hard deps; extraction inherits proven infra
Golden-master expansion (0c)	Immediately before extraction	Needs Adam approval; captures current behavior incl. snapshot overlay
Calc-core extraction slices 1–4 (lib → budget-rules/registry → availability → engine)	P6, post-5G-2, pre-5G-4a (~Sep–Oct)	The pinch point; unblocks 5G-4, Budget identity, rollover
Recon builders + closeout extraction (slice 5)	After 5G-1D activation + Slice 7 + gap repairs	Slice 3 is about to modify that region; don't move a moving target
Legacy fetch-site migration to api.js	Opportunistic, per feature touched	Low value as standalone churn; free when riding a feature change
Register/Budget/view modularization decision	Post-rollover 2027, under the merged 5L/5I-4 label	Wendy-critical, weekly-evolving UI; extraction payoff currently negative
DO NOT DO		
A broad application-modularization phase in 2026	—	Serializes behind Wendy-critical UI risk and the calendar-forced chain (freeze → 5G-1B clocks → rollover deadline) for payoff the ES-module rule already delivers on new code
Extract anything while 5G-1D Slices 3/6/7 are in flight, or during the freeze	—	Same file, same regions, no merges allowed anyway
Big-bang rewrite of the 58 fetch call sites, event handlers, or renderers	—	Pure churn across every feature at once; breaks the M4 slice-tests for zero behavior gain
Split CSS/HTML out of index.html	—	No maintainability payoff; touches the BUILD_TS stamping path
Move getCurrentWeek/date pins behaviorally during extraction	—	They are rollover-phase design work; extraction only relocates them
8. Does the canonical roadmap need a distinct application-modularization phase?
No. It needs three smaller things instead:
A widened, explicit charter for the existing calc-core extraction slot (P6) — the four seams + constants externalization it already promises, plus the riders this review adds: js/lib utilities, the buildModelInputs() adapter (retiring preview-by-global-mutation), the window-bridge contract, and the test-harness repoint. That charter, not a new phase, is where "application modularization" genuinely pays for itself, because it is the only region where structure currently blocks planned work (5G-4, Budget identity, rollover).
Module infrastructure attached to 5G-2, not to a phase of its own — static-server e2e mode, js/data/api.js, and the first js/features/ module prove the pipeline on new code where regression risk is zero.
The deferred modernization label kept deferred — 5L merged with 5I-4 per the roadmap review, revisited after the 2027 rollover with a pull-based trigger (e.g., the first Wendy-facing feature that is materially harder because Register/Budget live in-file). The three 2026-07-12 reviews independently reached this same conclusion, and nothing in the code contradicts them: the monolith's dangerous part is the engine and its test coupling; the bulky part (rendering) is stable, disciplined, and cheap to leave alone.
One caveat worth recording in the phase doc: if 5G-1D activation slips far enough that extraction would collide with the rollover's calendar chain, extraction wins the collision — the rollover executed against an un-extracted engine is the single worst-case scenario this review identified (hand-editing per-year constants inside a frozen 10k-line file under a hard deadline).
If you want, I can file this as docs/reviews/application-modularization-review-2026-07-13.md (matching your review-doc conventions) and/or draft the extraction-phase charter page (0d) as a follow-up — say the word and I'll write either. Nothing has been changed in the repo.

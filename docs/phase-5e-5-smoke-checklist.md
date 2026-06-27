# Phase 5E-5 — Budget Line Admin: Manual Smoke Checklist

Date: 2026-06-27  
Tester: Adam Herndon  
URL: https://dashboard.herndons.us  

All tests use real July 2026 data. No accidental mutations — follow the sequence; each step either uses intended changes or is explicitly reversible.

---

## Pre-flight

- [ ] Hard refresh (Cmd+Shift+R) to clear cache
- [ ] Confirm logged in as Adam (owner role)
- [ ] Navigate to Budget → July 2026
- [ ] Confirm "Manage Lines" button appears in header (right of month selector)
- [ ] Confirm Edit/Archive buttons appear on each expense line row
- [ ] Confirm Edit button (no Archive) appears on income rows (Net Salary, Net Salary Spouse)
- [ ] Confirm Wendy (household_admin) ALSO sees Manage Lines / Edit / Archive — this is intentional; Wendy can manage household budget rules via `canWriteFinancials()`
- [ ] Confirm unauthenticated users do NOT see or cannot use admin controls (sign out to verify)

---

## AC-1: Edit misc.goal_sweep from July forward — June unchanged

1. Click **Edit** next to "Extra Pay Going to Spreadsheet" (Misc section, July)
2. Confirm modal shows:
   - Category: Extra Pay Going to Spreadsheet
   - Group: Misc.
   - Scope: From July 2026 forward (locked — no scope choice)
   - Current Amount: $1,450.00
3. Change amount to **$1,400** (test value)
4. Click Save
5. Confirm Budget re-renders: goal_sweep now shows $1,400 in July
6. Confirm Budget Balance row updates (should now show $50 out of balance)
7. Switch to **June 2026** — confirm goal_sweep still shows $2,300
8. **Restore**: Click Edit on goal_sweep in July, change back to **$1,450**, Save
9. Confirm July budget balances to $0 again

---

## AC-2: Edit misc.extra from July forward — Budget Balance updates

1. Click **Edit** next to "Extra" (Misc section, July)
2. Change amount to **$1,800** (from $1,869)
3. Click Save
4. Confirm Budget Balance row shows **$69 out of balance** (income $15,938 - planned $15,869 = +$69)
5. **Restore**: Click Edit on Extra in July, change back to **$1,869**, Save
6. Confirm balance returns to $0

---

## AC-3: Add a one-time July rule using an existing registry key

1. Click **Manage Lines** (opens Add modal)
2. Select category: "Wendy GLP Meds" (health_fitness.wendy_glp_meds) — currently active Aug-Dec only
3. Label auto-fills to "Wendy GLP Meds"
4. Amount: **200**
5. Scope: **One-time (July 2026 only)**
6. Click Add Rule
7. Confirm "Wendy GLP Meds" appears in Health & Fitness for July at $200
8. Switch to **June 2026** — confirm row does NOT appear
9. Switch to **August 2026** — confirm only the seed row ($404, start Aug) appears, not the one-time $200 row
10. **Cleanup**: Click Archive on the $200 row in July; confirm it disappears from July
11. Confirm August and June are still correct

---

## AC-4: Add an ongoing rule from July forward

1. Click **Manage Lines**
2. Select category: (pick a currently-inactive leaf key, e.g., "Personal Care > Hair" — already active, so pick something inactive like a future addition, or skip this test if no inactive leaf is available)

> **Note:** If all leaf keys are already active for July, the dropdown will show them all as disabled. In this case, skip AC-4 and document it: all registry keys are active in July 2026.

If a valid inactive key is available:
1. Select it, enter label and amount **$50**, Scope: **Ongoing from July 2026 forward**
2. Click Add Rule
3. Confirm row appears in July and August
4. Confirm row does NOT appear in June
5. **Cleanup**: Archive it in July — confirm it disappears

---

## AC-5: Archive modal — verify Case A and Case B display (no real rows archived)

Test modal display logic only for both cases. Cancel every time — do not archive real rows.

**Case A — row has prior-month history (caseA = start_month < July)**

1. Click **Archive** on "Mortgage & Rent" (home.mortgage_rent) in July 2026
   - This row started before July, so it has history
2. Confirm modal shows:
   - Title: "Archive Budget Rule"
   - Indicates this rule has history before July 2026
   - Explains it will be closed at end of June 2026 (end_month set to 2026-06-01)
   - Row will remain visible in all months before July
3. Click **Cancel** — do not archive

**Case B — row started this month (caseB = start_month = July)**

1. Click **Archive** on "Diablos (Preston) Fee" (health_fitness.diablos_preston_fee) in July 2026
   - This row starts July 2026, so it has no prior history
2. Confirm modal shows:
   - Title: "Archive Budget Rule"
   - Indicates this rule started in July 2026 (no prior history)
   - Explains it will be deactivated (is_active set to false) if confirmed
   - Does NOT say "will be closed at end of June"
3. Click **Cancel** — do not archive

> Both cancel paths must dismiss the modal cleanly with no state change.

---

## AC-6: Duplicate active key blocked

1. Click **Manage Lines**
2. Select "Mortgage & Rent" (home.mortgage_rent) — already active for July
3. Note: the dropdown should show "Mortgage & Rent (active this month)" — key should be **disabled**
4. If somehow selectable, enter amount and try to save — confirm error: "An active rule already exists"
5. Click Cancel

---

## AC-7: Changes persist after refresh

1. Make a real change: Edit misc.extra → change to $1,800, Save
2. Hard refresh (Cmd+Shift+R)
3. Confirm Budget → July shows misc.extra at $1,800 (not $1,869)
4. **Restore**: Edit misc.extra → $1,869, Save, hard refresh, confirm $1,869 again

---

## AC-8: Totals recalculate after each change

Verified implicitly in AC-1, AC-2, AC-3. Confirm:
- [ ] Total Planned Budget row updates after each save
- [ ] Budget Balance row (income − planned) updates correctly
- [ ] Green "✓ Budget balanced" appears when $0 difference
- [ ] Amber "⚠ Budget out of balance" appears when difference ≠ $0

---

## AC-9: Write access is role-gated

**Unauthenticated:**
1. Sign out
2. Confirm Manage Lines button NOT visible (or not functional if visible)
3. Confirm Edit/Archive buttons NOT visible on rows
4. Sign back in as Adam

**Wendy (household_admin) — intentionally allowed:**
- Wendy should see Manage Lines, Edit, and Archive buttons
- This is correct behavior — `canWriteFinancials()` includes household_admin
- Wendy can manage budget rule labels, amounts, one-time/ongoing adds, and archives
- This was verified in pre-flight above

**Future viewer role (not yet implemented):**
- Once a viewer/read-only role exists, it must NOT see or be able to use admin controls
- Enforcement deferred to 5E-6 Role Enforcement phase

---

## AC-10a: Edit preserves original end_month (date-range preservation)

This tests the hardening fix: editing a rule with a fixed end date must NOT convert it to open-ended.

1. Identify a budget line with a known end date (e.g., "Diablos (Preston) Fee" — end_month = 2026-12-01)
2. Click **Edit** on that row in July 2026
3. Confirm the modal "Effective Range" shows: **"From July 2026 through December 2026"** (not "onward (open-ended)")
4. Change the amount by $1 and click Save
5. In July: confirm the row shows the new amount
6. In January 2027: confirm the row does NOT appear (end_month preserved at Dec 2026)
7. **Restore**: Click Edit on that row in July, change amount back, Save. Confirm January 2027 still clean.

> If all editable rows are open-ended in your test data, note that here and verify the "onward (open-ended)" label displays correctly instead.

---

## AC-10: No invisible rows for unknown keys

- Confirm all rows added via the admin UI (using registry keys) appear in the Budget table
- Confirm no row was created with a key outside BUDGET_CATEGORY_REGISTRY
- (Static regression test 5E5-15 and 5E5-18 cover this mechanically)

---

## Post-smoke state check

- [ ] Budget July 2026 shows: Total Income $15,938, Total Planned $15,938, Balance $0
- [ ] misc.goal_sweep = $1,450
- [ ] misc.extra = $1,869
- [ ] All restored to pre-smoke state

---

## Sign-off

Tester: _______________  Date: _______________  
Result: PASS / FAIL  
Notes:

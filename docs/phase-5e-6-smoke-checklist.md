# Phase 5E-6 — Monthly Entertainment Buckets: Manual Smoke Checklist

Date: _______________  
Tester: Adam Herndon  
URL: https://dashboard.herndons.us  
Prerequisite: phase-5e-6-migration.sql has been run in Supabase and validated.

---

## Wendy Operating Convention — July 2026 Weekly Buckets

Entertainment weekly buckets follow a calendar-week convention for July 2026:
- **Week 1**: July 1–7
- **Week 2**: July 8–14
- **Week 3**: July 15–21
- **Week 4**: July 22–31

No date enforcement in the app. This is a household convention so Wendy knows which weekly bucket to use. Assign transactions to the week matching when the spending occurred.

For event buckets (Seattle, Wewe's Lunches): assign the transaction to the event bucket, not a weekly bucket. Do not double-count.

---

## Pre-flight

- [ ] Hard refresh (Cmd+Shift+R)
- [ ] Confirm logged in as Adam (owner role)
- [ ] Navigate to Budget → July 2026
- [ ] Confirm budget is balanced: Total Income $15,938, Total Planned $15,938, Balance $0
- [ ] Confirm "Manage Lines" button and Edit/Archive buttons are visible

---

## AC-1: Entertainment renders as a parent/group in July 2026

1. In Budget → July 2026, locate the **Entertainment** section
2. Confirm Entertainment renders as a **group header** (bold, with sub-rows below)
3. Confirm the following six child rows appear under Entertainment, in any order:
   - Seattle — $300
   - Wewe's Lunches — $200
   - Entertainment Week 1 — $250
   - Entertainment Week 2 — $250
   - Entertainment Week 3 — $250
   - Entertainment Week 4 — $250
4. Confirm the **Entertainment group total** shows: Spent —, Budget $1,500, Remaining $1,500 (or similar)
5. Confirm no 7th entertainment row appears
6. Confirm no "Entertainment" standalone leaf row — the parent is a header only

---

## AC-2: July Budget remains balanced at $0

1. In Budget → July 2026, confirm:
   - Total Income: $15,938
   - Total Planned Budget: $15,938
   - Budget Balance: $0 (green "✓ Budget balanced")
2. The Entertainment restructure is net $0 (parent $1,500 removed, 6 children sum to $1,500)

---

## AC-3: June history remains intact

1. Navigate to Budget → **June 2026**
2. Confirm Entertainment still appears, showing historical data:
   - Group header: Entertainment
   - Either one consolidated budget row OR group header with correct budget total ($1,500)
   - Any June entertainment transactions still show (if any exist)
3. Confirm June Total Planned Budget is unchanged
4. Confirm no July child rows appear in June (Seattle, Wewe's Lunches, Week 1–4 should NOT appear)

---

## AC-4: Future months do not inherit July-only lines

1. Navigate to Budget → **August 2026**
2. Confirm Entertainment either:
   - Does NOT appear (no active child rules for August), OR
   - Shows only explicitly-added August rules (there should be none immediately after migration)
3. Confirm "Seattle", "Wewe's Lunches", "Entertainment Week 1–4" do NOT appear in August
4. Navigate to Budget → **September 2026** and repeat the same check

---

## AC-5: Budget grid shows BLR line_label, not registry label

1. In Budget → July 2026, confirm child rows show:
   - **Seattle** (not "Entertainment Event 1")
   - **Wewe's Lunches** (not "Entertainment Event 2")
   - **Entertainment Week 1** (registry label and BLR label match for week slots)
2. This confirms `_getCategoryDisplayLabel` is working in the budget grid

---

## AC-6: Budget Line Admin — edit a July child row

1. Click **Edit** next to "Seattle" (entertainment.event_1) in July 2026
2. Confirm modal shows:
   - Category: Entertainment Event 1 (registry key)
   - Line Label: Seattle
   - Amount: 300
   - Effective Range: From July 2026 through July 2026 (one-time rule)
3. Change amount to **$280** (test value)
4. Click Save
5. Confirm Seattle now shows $280 in July; group total adjusts to $1,480; July goes out of balance by $20
6. **Restore**: Click Edit on Seattle → change back to **$300** → Save
7. Confirm July balance returns to $0

---

## AC-7: Budget Line Admin — activate an inactive slot for a future month

1. Navigate to Budget → **August 2026**
2. Click **Manage Lines**
3. In the Add modal, select **Entertainment Event 1** (should be selectable, no active August rule)
4. Enter label: **Braves Game**, amount: **$150**, scope: **One-time (August 2026 only)**
5. Click Add Rule
6. Confirm August Entertainment shows: Braves Game — $150
7. Confirm July Entertainment is unchanged (still shows Seattle, not Braves Game)
8. **Cleanup**: Click Archive on "Braves Game" in August → confirm it disappears
9. Confirm August entertainment returns to empty

---

## AC-8: Transaction form — date-aware dropdown labels

1. In Budget → July 2026, click **+ Add Transaction**
2. Confirm date defaults to July 2026
3. Confirm category dropdown shows Entertainment child slots with **July labels**:
   - Under "Entertainment" optgroup:
     - **Seattle** (entertainment.event_1)
     - **Wewe's Lunches** (entertainment.event_2)
     - **Entertainment Week 1** (entertainment.week_1)
     - **Entertainment Week 2** (entertainment.week_2)
     - **Entertainment Week 3** (entertainment.week_3)
     - **Entertainment Week 4** (entertainment.week_4)
     - Entertainment Event 3, 4, 5 and Week 5 (registry fallback labels — no July BLR)
4. **Entertainment** parent is NOT in the dropdown (it is non-assignable)
5. Change the transaction date to **August 2026** (any August date)
6. Confirm the dropdown refreshes: Entertainment child labels revert to registry fallback labels
   ("Entertainment Event 1", "Entertainment Event 2", etc.) since no August BLR rules exist
7. Click **Cancel** — do not save

---

## AC-9: Transaction register — saved transactions display July label

1. Add a real test transaction:
   - Date: July 10, 2026
   - Category: entertainment.event_1 (labeled "Seattle")
   - Amount: $25
   - Description: "AC-9 smoke test"
   - Save
2. Confirm the transaction appears in the July register with category showing **Seattle**
3. Navigate to a different month and back to confirm persistence
4. **Cleanup**: Click Del on the test transaction → confirm it's removed

---

## AC-10: Legacy entertainment transactions display safely

1. In Budget → **June 2026**, scroll to the Transactions section
2. If any transactions exist with category_key `entertainment` (old standalone key):
   - Confirm they display with label "Entertainment" (registry fallback) or the June BLR line_label
   - Confirm they are NOT invisible or broken
3. If editing one of those legacy transactions:
   - Click Edit
   - Confirm the category field shows **"Entertainment (legacy — re-categorize)"** as the selected option
   - Confirm you can re-categorize to a child slot if desired
   - Click Cancel — do not save

> If no legacy entertainment transactions exist in June, mark this test N/A and document.

---

## AC-11: Duplicate Entertainment label blocked

1. Navigate to Budget → July 2026
2. Click **Manage Lines** → select **Entertainment Event 3** (inactive for July)
3. Enter label: **Seattle** (same as entertainment.event_1), amount: $100, scope: One-time July 2026
4. Click Add Rule
5. Confirm error: "Another Entertainment line with the label 'Seattle' already overlaps this date range. Use a different label."
6. Change label to **"Movies"** → click Add Rule → confirm it saves
7. **Cleanup**: Archive the new "Movies" rule → confirm it disappears from July

---

## AC-12: Inactive slots do not appear as visible budget rows

1. In Budget → July 2026, confirm:
   - entertainment.event_3, event_4, event_5 do NOT appear as rows (inactive for July)
   - entertainment.week_5 does NOT appear (inactive for July)
2. Only the 6 activated child rows are visible

---

## Post-smoke state check

- [ ] July Budget: Total Income $15,938, Total Planned $15,938, Balance $0
- [ ] Entertainment group: 6 active child rows totaling $1,500
- [ ] Seattle $300, Wewe's Lunches $200, Week 1–4 each $250
- [ ] June history intact — Entertainment shows $1,500 historical budget
- [ ] No August/future Entertainment rows (unless added and cleaned up during AC-7)
- [ ] All test transactions from smoke run have been deleted

---

## Sign-off

Tester: _______________  Date: _______________  
Result: PASS / FAIL  
Notes:

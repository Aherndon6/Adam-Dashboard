# Herndon Financial OS — Status

Last updated: 2026-06-15

## What It Is
Single-file HTML app (`index.html`) served via GitHub Pages at `dashboard.herndons.us`. Tracks weekly finances, goals, tasks, notes, and wishlists. All persistent data lives in Supabase.

## Supabase Tables
| Table | Purpose |
|---|---|
| `weekly_reconciliations` | Weekly financial data |
| `weekly_tasks` | Standard weekly tasks |
| `weekly_notes` | Notes per week |
| `model_week_overrides` | Overrides to the financial model |
| `goals` | Key-value store — `value` column is **numeric**, cannot store JSON |
| `wishlist_items` | Wishlist entries |
| `custom_tasks` | Custom required actions added by user (created 2026-06-15) |

**Important:** The `goals.value` column is `numeric` type. Never try to store JSON or text there — it will fail with HTTP 400 silently.

## custom_tasks Table (new as of 2026-06-15)
```sql
CREATE TABLE custom_tasks (
  id TEXT PRIMARY KEY,
  week_num INTEGER NOT NULL,
  label TEXT NOT NULL,
  completed BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
-- RLS: FOR ALL USING (true) WITH CHECK (true)
```
- `week_num` is the index used in the app (e.g., week index 3 = Week 25 in the 2026 calendar)
- IDs are generated client-side: `ct_` + timestamp + random suffix

## CRUD Layer (in index.html)
- `saveCustomTask(weekNum)` — reads input, POSTs to Supabase
- `toggleCustomTask(weekNum, id, checked)` — PATCHes completed flag
- `deleteCustomTask(weekNum, id)` — DELETEs from Supabase
- `loadAll()` — fetches all 7 tables in parallel including `custom_tasks`

## Migration (completed 2026-06-15)
- Old storage: `localStorage` key `hfos_custom_tasks` (keyed by week index)
- Migration: on first load with 0 Supabase rows + localStorage data present, bulk POST to Supabase then clear localStorage
- Status: **complete** — the task "Review Jabian reimbursements..." (id: `ct_1781526354226_7804`) is in Supabase, localStorage is cleared
- Note: The reimbursement task is still active on the dashboard (Week 25); Adam plans to resolve it next week

## Known Issues / Watch Items
- `push_to_github.sh` has `set -e` — if `git commit` fails (nothing to commit), the push is silently skipped. Workaround: run `git push origin main` manually.
- GitHub Pages sometimes doesn't trigger on merge commits — use `git commit --allow-empty -m "Trigger Pages deploy" && git push origin main` if deploy doesn't fire.
- Terminal is "click-tier" in Cowork — Claude cannot type into it. User must run git commands directly.

## Version History
- v2.3: Change memo exists (`FOR_v2.3_Change_Memo.docx`)
- 2026-06-15: Added `custom_tasks` Supabase table; migrated from localStorage sync

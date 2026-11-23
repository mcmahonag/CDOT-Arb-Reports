# CDOT Arborist Reports

A web app for browsing the monthly arborist reports for CDOT's landscaped medians, triangles and streetscapes. You import the contractors' Excel workbooks as they come in. Every tree goes on a map and into a filterable table, with summaries by site and region and a history for each tree across months.

| Region | Contractor |
|---|---|
| North | Christy Webber |
| Southwest | Christy Webber |
| Central | A Safe Haven |
| Southeast | A Safe Haven |

Hosting is the same as the Reno tree app: static files on GitHub Pages, with Supabase holding the data behind an email + password sign-in.

## Files

| File | What it is |
|---|---|
| `index.html` | The app |
| `parser.js` | Reads a report workbook (one tab per site) into tree records |
| `config.js` | Your Supabase URL and anon key, plus the region and contractor list |
| `geocode.js` | Places trees on street centerlines |
| `data/centerlines.json` | City of Chicago street centerlines, trimmed to arterials plus the streets in the reports |
| `supabase/schema.sql` | Tables and access rules. Run this once in Supabase |
| `supabase/002_tree_locations.sql` | Saved tree positions (run if your database predates it) |
| `supabase/003_location_source.sql` | Records GPS accuracy on saved positions |
| `supabase/004_roles_field_reports.sql` | Staff/contractor roles, region-based access, field reports, photos |
| `supabase/005_work_orders.sql` | Work orders and the completion function that updates reports |
| `supabase/006_tree_ids.sql` | Permanent citywide tree IDs (T-10001…) and moves locations, notes, photos and orders onto them |
| `supabase/007_inventory.sql` | New GPS inventory table |

## Setup (about 15 minutes)

1. **Create a Supabase project** (the free tier is plenty) at supabase.com.
2. **Create the tables.** In Supabase, open *SQL Editor → New query*, paste in all of `supabase/schema.sql`, and click *Run*.
3. **Add users.** Go to *Authentication → Users → Add user*, enter an email and password, and check *Auto Confirm User*. Under *Authentication → Sign In / Providers → Email*, turn off *Allow new users to sign up* so only people you add can get in.
4. **Connect the app.** Under *Project Settings → API*, copy the Project URL and the `anon` `public` key into `config.js`.
5. **Publish on GitHub Pages.** Create a repo (e.g. `cdot-arborist-reports`) and upload these files. Then go to *Settings → Pages → Deploy from branch → main / root*. The app will be at `https://<your-user>.github.io/cdot-arborist-reports/`.
6. **Import the reports.** Sign in, click *Reports*, and choose the workbooks. The app guesses the region and month from each file name (e.g. "North … October 2026", "SW …", "ASH Central …"), and you can correct them before saving. Saving a region + month that already exists replaces it. To remove one, open *Reports* and click *Delete* next to it.

Without Supabase details in `config.js`, the app still works. Importing just shows the reports on that device and saves nothing.

## How the reports are read

- **Each site tab is read; the Summary and SortSheet tabs are skipped.** Tabs whose names end in "OLD" are also skipped. The importer lists anything it skipped.
- **Vacant spots.** "NO TREE" rows count as *vacant*, or as *removed* when they have a Tree Removed date.
- **Map positions** come from the City's Street Center Lines (`data/centerlines.json`). Each row's street number (e.g. 1600 W = Ashland) picks the street, and its address (e.g. 1608 N) is placed along that block's centerline. Spelling and abbreviations in the reports don't matter. Divided roads drawn as two one-way lines are averaged, so those trees land in the median. Diagonal streets (Archer, Ogden, Wacker) snap to the nearest point on the street. Anything left over can be dragged into place with **Adjust location** in the tree panel, and that position is kept for every future report.
- **Updating the centerlines:** download a new CSV from data.cityofchicago.org/d/6imu-meau and run `python3 tools/build_centerlines.py the-file.csv`. Add street names after the file name to include smaller streets.
- **Tree history.** A tree is matched across months by region + site + planter + tree number + address. If a contractor renumbers a site, the history for that site starts over.
- **Conditions flagged:** pests or disease noted, deadwood of 20% or more, an ISA hazard rating, lean, trunk wounds, and "Monitor" in the comments.

## Notes

- Your notes are saved per tree. Notes flagged *follow-up* show in the table and in the *My follow-ups* filter until you mark them resolved.
- *Export CSV* downloads whatever the current filters show.
- Keep the report workbooks out of the GitHub repo if it's public. The data lives in Supabase behind sign-in.

## Database updates (run in order, once each)

In Supabase → SQL Editor, run each file from the `supabase` folder:

1. `003_location_source.sql`
2. `004_roles_field_reports.sql`: everyone who already has a login becomes **staff**. It also creates the private `tree-photos` storage bucket. If that part errors, create a **private** bucket named `tree-photos` under Storage and run the file again.
3. `005_work_orders.sql`
4. `006_tree_ids.sql`: gives every tree already in the database a permanent ID.
5. `007_inventory.sql`

For a brand-new database, run `schema.sql`, then 004 through 007. Don't re-run `schema.sql` after 004, because it would re-open access to every signed-in user.

## Roles

- **Staff** see everything, import Excel reports, issue work orders, add notes and manage people.
- **Contractors** see only their regions. They fill in field reports, GPS trees, add trees and photos, and complete work orders. They can't see staff notes.
- **Pending:** every new login starts here with no access. Add the login in Supabase (Authentication → Users), then open **People** in the app to set the role, company and regions.

## Field reports (replacing the Excel)

1. Open **Reports** and choose **Start field report** for a region. The latest report's trees are copied into a draft for this month.
2. In the field, open a tree and choose **Edit inspection**. Saving marks it inspected, and the header shows "X of Y inspected". Use the *Not inspected yet* filter to find what's left.
3. You can also **GPS the tree**, **add a photo**, or use **＋ Add tree** for trees missing from the report.
4. **Submit** in Reports locks the draft for the contractor. Staff can **Reopen** it. **Excel** downloads any report in the original layout (one tab per site), with lat/long and who inspected each tree.

## Location survey

**📍 Survey locations** on the map opens a site's tree list with GPS running continuously. Stand at any tree, in any order (multi-row medians are fine), and tap **Here** on its card. You can tap a dot on the map to find its card. GPS points override the street-centerline estimate and carry forward to every future report. Staff can clear a site's GPS points to start over.

## Work orders

- **Issue:** staff issue an order from a tree's panel (prune, remove, treat, inspect), or use **Work order for these trees** to cover everything in the current filter, e.g. a storm event.
- **Alert:** contractors see a count on the **Work orders** button and a ring around each ordered tree on the map (red = urgent).
- **Complete:** **Mark complete** records the date and notes and updates the tree in the latest report. Prune sets the last-pruned date, remove marks the tree removed, and treat sets the treatment date.
- Alerts are in the app only. Email notifications would need an email service connected to Supabase.

## Tree IDs

- **Every tree has a permanent citywide ID** (`T-10001`, `T-10002`, …) that never changes or gets reused. Region isn't part of the ID, so it stays valid if contract boundaries move.
- **Importing a report** keeps each tree's ID by matching its location. If a planter, number or address changed, it matches by best guess against the previous report (same site, species, DBH) and flags the tree *Tree ID matched by best guess* for staff to confirm or split off with a new ID. Trees added in the field get new IDs.
- **Merge into…** in the tree panel (staff) combines two IDs that are the same physical tree. History, photos, notes and work orders move to the surviving ID.
- **Links:** `…/CDOT-Arb-Reports/?tree=T-10042` opens that tree, which works for QR tags. Excel exports include a Tree ID column, and re-importing an exported workbook keeps the IDs.

## New GPS inventory

The fresh location survey. Staff and contractors can collect it, each limited to their regions.

1. On the map, tap **🌳 New inventory**, then pick the region, site and (optionally) planter/row. GPS runs continuously, and the panel shows its accuracy.
2. Stand at the trunk and tap **📍 Drop tree here**. The form shows the old report's records for that site, nearest first. Tap the one that matches to keep its tree ID and history, with its species and DBH pre-filled for you to correct. Or choose **None of these** to give it a new ID.
3. **Required:** position number (pre-filled with the next number), condition, genus, species, DBH and a photo. Vacant spots need only position, condition and photo. The nearest street address is worked out from the centerlines.
4. **Nudge** moves a dot by dragging it on the map; use the Satellite view to check it. **Drop at map center** places a tree at the red cross instead of GPS.
5. **Old records not linked yet** lists what's left from the old report on that site. Mark trees that aren't there as **Not found**.
6. When a region is done, staff open **Reports** and choose **Publish as report**. The inventory becomes that region's base report (one tab per site in Excel), and future field reports start from it. Publishing again replaces it.

Saving an inventory tree also sets that tree ID's location everywhere, so linked trees move to their GPS position in the old reports straight away.


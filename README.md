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
| `supabase/002_tree_locations.sql` | Adds saved tree positions. Run it if you set up the database before this was added |

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

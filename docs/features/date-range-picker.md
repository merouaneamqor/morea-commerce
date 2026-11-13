# Date range picker

One picker on every page where the seller changes the dates, so it looks and behaves the same everywhere: `admin/shared/_date_range_picker` (partial) + `date_range_picker_controller.js` (Stimulus) + `DateRange` (the rules, in Ruby).

Pages using it: Tableau de bord, Comptabilité, Livraison, Publicités, Mes statistiques. (Commandes, Produits and the other pages have no date filter today; the Confirmation desk and the expenses list keep their own fixed period links for now.)

## What the seller sees
- **Shortcuts:** Aujourd'hui, Hier, 3 / 7 / 30 derniers jours, Ce mois, Mois dernier, Cette année, T1 to T4 (a quarter that has not started is not offered; the running one stops today), Plage personnalisée. A shortcut applies at once and is a plain link, so it works without scripts.
- **Plage personnalisée:** two months side by side (one on a phone), arrows between months, weeks start on Monday. First click is the start, second the end, the days in between are highlighted, a second click before the first swaps them. "Date de début" and "Date de fin" on top, the number of days at the bottom. Nothing changes until **Appliquer**; **Annuler**, Escape or a click outside close it without changing anything. Days after today cannot be picked and the next-month arrow stops at the current month.
- **The button** shows the shortcut's name ("Ce mois") or the dates ("3 oct. → 15 oct. 2026", one day: "3 nov. 2026", across years: "30 déc. 2025 → 3 janv. 2026").
- **Phone:** the panel is a bottom sheet, shortcuts on top, the calendar opens behind "Plage personnalisée". **Languages:** French, English, Arabic (right to left: the earlier month on the right, arrows mirrored). Digits stay Latin.

## Rules (`DateRange`)
- **Store days.** Days are `Africa/Casablanca` days. The picker's "today" comes from the server; the browser's clock and timezone are never used. Offsets follow the tz database on each date (including Ramadan), never a fixed +1.
- **Inclusive end.** `3 Nov to 3 Nov` is the whole day, `00:00:00` to `23:59:59.999999`. Queries use `range.time_range` (an exclusive end at the next midnight), so an order at 23:59 on the last day counts and one at 00:00 the next day does not.
- **No future.** An end after today is cut to today; a range that starts after today is ignored. A start after the end is swapped. A range of more than five years is ignored, not silently shortened.
- **Previous period.** The same number of days just before (10 days: the 10 days before), with no gap and no overlap. "% vs previous period" on the dashboard and on Comptabilité use `range.previous`.

## URL and memory
- The range is in the URL: `?from=2026-10-01&to=2026-10-31`, so a refresh or a shared link keeps it. A shortcut also adds `&preset=last_month` (it only names the button; it is ignored unless it really is that range, which matters when two shortcuts are the same days, e.g. "Ce mois" and "3 derniers jours" on the 3rd).
- Bad, partial or damaged dates are ignored, never an error. Then the page uses the last choice, then its default (Dashboard 7 days, Comptabilité this month, others 30 days; Mes statistiques this month).
- **Last choice:** remembered per page in an HttpOnly cookie for a year. A shortcut is remembered by name (so "7 derniers jours" stays the last 7 days next week), a custom range by its dates. The URL always wins over the cookie.
- Older links keep working: `?period=7d` (dashboard), `?period=week` (Mes statistiques), `?month=2026-10` (Comptabilité), `?start_date=&end_date=` (Livraison, Publicités).

## Adding it to a page
In the controller: `include DateRangeSelection` and `@date_range = selected_date_range(scope: "page_name", default: "last_30")` (it also sets `@date_range_preset`). Then `range.time_range` for the orders (or `range.from` / `range.to` for date columns) and `range.previous` for the comparison. In the view: `render "admin/shared/date_range_picker", range: @date_range, preset: @date_range_preset, url: page_path` (`extra:` keeps other filters, `align: "start"` opens to the right, `theme: "dark"` for a dark header).

## Tests
`spec/services/date_range_spec.rb` (the rules), `spec/requests/date_range_picker_spec.rb` (the component, the pages, memory), plus the page specs. The clicking inside the calendar is script and was checked in a real browser (open, two months, no future day, swap, highlight, start = end, month arrows, Annuler, Appliquer, memory, phone, Arabic); there is no browser test setup in the project yet.

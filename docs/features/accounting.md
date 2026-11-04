# Comptabilité (accounting)

Page `/comptabilite`, reserved to the store owner and managers (store admins; confirmation agents never see it). Every number on it, and in its export, comes from one class: `AccountingStats`.

## Rules that keep the numbers exact

- **Whole centimes.** Every amount is an integer number of centimes. Ratios are `Rational` (exact fractions). Only the view rounds (`AccountingHelper`), once, when it prints.
- **One source.** `AccountingStats` builds *lines* (one per delivered order, one per returned order, one per day of ad spend). Totals, daily curves, the "100 MAD" split and the export (`AccountingExport`) are sums of those same lines.
- **Frozen at the time.**
  - Cost of goods: `order_items.unit_cost_cents`, copied from the product when the order is placed.
  - Delivery fee: `orders.delivery_fee_cents`, frozen when the order is delivered. Return fee: `orders.return_fee_cents`, frozen when it is returned. Source: the fee Sendit reported for the parcel, else the default of the workspace's *one* active delivery account that has one; unknown stays `NULL` (counted as 0 and flagged), never guessed. A fee that arrives later fills an empty value only; a frozen value is never overwritten.
  - Changing a product cost or a carrier fee later does not move past months.
- **Store days.** Months and days are Africa/Casablanca days (23:59 on the 31st is in the month, 00:00:30 on the 1st is not).

## Which orders count

Money only comes in when a COD order is delivered.

| Mode | Delivered orders (revenue, cost of goods, delivery fee) | Returned orders (return fee only) |
| --- | --- | --- |
| Livrées | by `delivered_at` | by `returned_at` |
| Expédiées | by `shipped_at` | by `shipped_at` |

Cancelled, new, confirmed, in-transit, unreachable and postponed orders never count. A returned or refused order has no revenue and no cost of goods (the product is back in stock); its return fee is an expense. Archived delivered orders still count.

## Formulas

```
gross margin   = revenue - cost of goods
total expenses = cost of goods + delivery fees (delivery and return) + advertising
net profit     = revenue - total expenses            # so expenses + net profit = revenue
average basket = revenue / delivered orders          # "—" with no delivered order
profit margin  = net profit / revenue                # "—" with no revenue
```

- **Advertising:** Meta spend already converted to the store currency (campaign rows; ad rows are the same money at another level and are never added). A day's decimals are added, then turned into centimes once, half up. Rows in another currency or without a conversion are left out and reported. Stays 0 until Meta (TikTok later) is connected.
- **Change vs previous period:** the previous period of the same length (October: 31 days, 31 August to 30 September). The current month counts to date and is compared with the same number of days before. Previous value 0: "Nouveau" (nothing to compare when both are 0: "—"). Profit margin moves in points.
- **"Où vont 100 MAD":** each part is its share of revenue in tenths of a point; the biggest remainders get the last tenths, so the four parts are exactly 100.0. In a month that loses money, profit is 0 and the three expenses share the 100.
- **Créances:** delivered parcels whose COD cash was not recorded as received (all time). **Inventaire:** stock x purchase cost (products without a cost are left out and counted). **Dettes:** no data yet (suppliers and agent payouts are not recorded).

## Always-true checks

`AccountingStats#invariants` returns an empty list when: gross margin = revenue - goods; expenses + net = revenue; the split adds up to 1000 tenths; totals = sum of lines; the daily figures add up to the month. The specs assert them on hand-worked data and on random orders, and check that the export's totals row equals the sum of its rows.

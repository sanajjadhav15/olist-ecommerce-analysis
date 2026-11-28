/*
Q2: Category contribution
Question: Which product categories bring the most seller sales, and how concentrated is revenue?

Definitions:
  - revenue = sum of order_items.price (freight excluded), same as Q1.
  - category = English name from category_translation (Portuguese name where no translation exists).
  - % of total = category revenue / revenue of ALL categories, including Uncategorised.
  - cumulative % = running revenue in descending order / the same total.
Statuses excluded: canceled, unavailable (same as Q1).
Dates: all dates are used. Q2 ranks categories, it does not read a trend, so thin months are not removed.
Fallbacks (COALESCE order): English name, then Portuguese name (2 untranslated categories),
  then 'Uncategorised' (610 products with no category).
Uncategorised is kept in the data and not filtered out. It ranks 21st (R$178,572.55),
  so it does not displace any top-10 category (DECISIONS.md entry 9).

Assumptions / notes:
  - products.product_id and category_translation.product_category_name were each checked
    to be unique (32,951 and 71 rows), so the joins are many-to-one and cannot multiply price.
    The database does not enforce this (no primary keys added), it is a fact about the data.
  - Left joins from order_items keep revenue even if a product or translation is missing.
  - Percentages are rounded to 2 decimals, so all categories add up to 100.01, not exactly 100.
  - The grand total is computed before LIMIT 10, so percentages are shares of all revenue,
    not of the top 10.
*/

-- Top 10 categories by revenue, with share and cumulative share
-- Tests: how concentrated seller sales are across categories.
-- Found: top category: health_beauty, with 9.31% and the cumulative % at row 10 is 62.37%.
with category_revenue as (
    select coalesce(ct.product_category_name_english, p.product_category_name, 'Uncategorised') as category,
           round(sum(oi.price)::numeric, 2) as revenue
    from orders o
    join order_items oi on o.order_id = oi.order_id
    left join products p on oi.product_id = p.product_id
    left join category_translation ct on ct.product_category_name = p.product_category_name
    where o.order_status not in ('unavailable', 'canceled')
    group by 1
),
shares as (
    select category,
           revenue,
           round(revenue * 100.0 / sum(revenue) over (), 2) as pct_of_total,
           round(sum(revenue) over (order by revenue desc, category) * 100.0
                 / sum(revenue) over (), 2) as cumulative_pct
    from category_revenue
)
select category, revenue, pct_of_total, cumulative_pct
from shares
order by revenue desc, category
limit 10;

/*
Checks:
  - Sum of category revenues = direct SUM(price) with the same status filter: matched.
  - Percentages across all categories add up to 100.01 (rounding).
  - Cumulative % on row 10 is below 100 because only 10 rows are kept.
  - Uncategorised ranks 21st, so it does not affect the top 10.

Limitations:
  - Categories are the dataset's own groupings, and 2 have no English translation.
  - Item-level revenue ignores freight and Olist's fee.
*/
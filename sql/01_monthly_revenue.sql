/*
Q1: Monthly revenue and month-over-month growth
Question: How does monthly seller sales change over time?

Definitions:
  - revenue = sum of order_items.price. Freight is excluded because it pays for shipping,
    not for the product (DECISIONS.md entry 1).
  - month = calendar month of order_purchase_timestamp.
  - growth % = (this month - previous month) / previous month * 100.
Statuses excluded: canceled, unavailable (DECISIONS.md entry 6).
Months included: Jan 2017 to Aug 2018. Every month in this range has at least 100 orders
  and the series is contiguous, so LAG always compares with the real previous month.
  Excluded: Sep 2016 to Dec 2016 (thin or missing months, which would break LAG)
  and Sep to Oct 2018 (partial months).

Assumptions / notes:
  - Orders are assigned to the month they were purchased, not delivered.
  - Plain JOIN is used because orders with no items add nothing to SUM(price).
  - Only order_items is joined, so price is never multiplied by another join.
  - Jan 2017 has no previous month in the series, so its growth is NULL.
  - Revenue is in Brazilian reais (R$), as recorded in the dataset.
*/


-- Step 1: monthly revenue only
-- Tests: seller sales per month for the included range.
-- Found: revenue starts at R$120,098.27 in Jan 2017, grows through 2017 and peaks in Nov 2017,
--        and ends at R$848,860.10 in Aug 2018.
select date_trunc('month', o.order_purchase_timestamp) as month,
       round(sum(oi.price)::numeric, 2) as revenue
from orders o
join order_items oi on o.order_id = oi.order_id
where o.order_purchase_timestamp >= '2017-01-01'
  and o.order_purchase_timestamp <  '2018-09-01'
  and o.order_status not in ('canceled', 'unavailable')
group by month
order by month;


-- Step 2: monthly revenue with month-over-month growth
-- Tests: how much revenue changed compared with the previous month.
-- Found:
--   - Feb 2017 has the largest growth, about 104%. This is a small-base effect: Jan 2017
--     revenue was only about R$120k, so early percentages look large.
--   - Nov 2017 grew about 52% (the peak month), then Dec 2017 fell about 26%.
--   - From early 2018 revenue plateaus, with small ups and downs of a few percent.
with monthly as (
    select date_trunc('month', o.order_purchase_timestamp) as month,
           round(sum(oi.price)::numeric, 2) as revenue
    from orders o
    join order_items oi on o.order_id = oi.order_id
    where o.order_purchase_timestamp >= '2017-01-01'
      and o.order_purchase_timestamp <  '2018-09-01'
      and o.order_status not in ('canceled', 'unavailable')
    group by month
),
with_prev as (
    select month,
           revenue,
           lag(revenue) over (order by month) as previous_revenue
    from monthly
)
select month,
       revenue,
       previous_revenue,
       round((revenue - previous_revenue) / nullif(previous_revenue, 0) * 100, 2) as growth_pct
from with_prev
order by month;


-- Step 3: months ranked by growth
-- Tests: which months had the largest increases and the largest drops.
-- Found: the top row is the largest increase and the bottom row is the largest drop.
--        Jan 2017 (NULL growth) is placed last by NULLS LAST.
with monthly as (
    select date_trunc('month', o.order_purchase_timestamp) as month,
           round(sum(oi.price)::numeric, 2) as revenue
    from orders o
    join order_items oi on o.order_id = oi.order_id
    where o.order_purchase_timestamp >= '2017-01-01'
      and o.order_purchase_timestamp <  '2018-09-01'
      and o.order_status not in ('canceled', 'unavailable')
    group by month
),
with_prev as (
    select month,
           revenue,
           lag(revenue) over (order by month) as previous_revenue
    from monthly
)
select month,
       revenue,
       round((revenue - previous_revenue) / nullif(previous_revenue, 0) * 100, 2) as growth_pct
from with_prev
order by growth_pct desc nulls last;


-- Check: total of monthly revenue equals a direct SUM with the same filters
-- Tests: that grouping by month loses or double counts nothing.
-- Found: both numbers match.
with monthly as (
    select date_trunc('month', o.order_purchase_timestamp) as month,
           round(sum(oi.price)::numeric, 2) as revenue
    from orders o
    join order_items oi on o.order_id = oi.order_id
    where o.order_purchase_timestamp >= '2017-01-01'
      and o.order_purchase_timestamp <  '2018-09-01'
      and o.order_status not in ('canceled', 'unavailable')
    group by month
)
select (select sum(revenue) from monthly) as sum_of_months,
       (select round(sum(oi.price)::numeric, 2)
        from orders o
        join order_items oi on o.order_id = oi.order_id
        where o.order_purchase_timestamp >= '2017-01-01'
          and o.order_purchase_timestamp <  '2018-09-01'
          and o.order_status not in ('canceled', 'unavailable')) as direct_total;


/*
Checks:
  - Sum of the monthly revenue = direct SUM(price) with the same filters (check query above).
  - Item rows after the join = item rows for the same orders, so no multiplication.
  - One month hand-checked against a one-month filter: same result.
  - Jan 2017 growth is NULL because there is no earlier month in the series.

Limitations:
  - Only one November is in the data (Nov 2016 is missing), so the Nov 2017 peak cannot be
    separated into seasonality (for example Black Friday) and general growth.
  - Revenue excludes freight and Olist's own fee, so it measures seller sales, not Olist's income.
*/
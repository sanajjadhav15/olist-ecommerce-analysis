/*
File: 00_checks.sql
Purpose: sanity checks on the raw tables before any analysis.
Findings that changed my approach are logged in DECISIONS.md.
*/

-- Check 1: customers
-- Tests: is customer_id unique per row, and how does it compare to customer_unique_id?
-- Found: 99,441 rows and 99,441 distinct customer_id values, but only 96,096 distinct customer_unique_id values.
-- customer_id is assigned per order, so it is not a person-level key.
-- Use customer_unique_id for person-level counts and customer_id only for joins.
select count(*) as total_rows,
       count(distinct customer_id) as unique_customer_ids,
       count(distinct customer_unique_id) as unique_people
from customers;

-- Check 2: order_items grain
-- Tests: how many distinct orders exist in order_items, and is it one row per order?
-- Found: 112,650 item rows represent 98,666 distinct orders.
-- This table is one row per item, not per order. count(*) counts item rows, not orders.
select count(*) as total_rows,
       count(distinct order_id) as unique_orders
from order_items;

-- Check 3: largest orders
-- Tests: what is the maximum number of item rows in one order?
-- Found: the largest order has 21 rows. The next largest have 20, 20, 15 and 15.
select count(*) as total_items, order_id
from order_items
group by order_id
order by total_items desc
limit 5;

-- Check 4: multi-item orders
-- Tests: how many orders have more than one item row?
-- Found: 9,803 orders (about 9.9% of orders in order_items) have more than one item row.
-- There is no quantity column. In the one order I inspected, the repeated rows had the same
-- product_id and price, so they appear to be separate units of the same product.
select count(*) as multi_item_orders
from (
    select order_id
    from order_items
    group by order_id
    having count(*) > 1
) as t;

-- Check 5: order_payments grain
-- Tests: how many payment rows and distinct orders are in the payments table?
-- Found: 103,886 rows cover 99,440 of the 99,441 orders. One order has no payment row.
-- Split payments (for example voucher plus card) create several rows per order,
-- so payments must be aggregated to order level before joining.
select count(*) as total_rows,
       count(distinct order_id) as unique_orders
from order_payments;

-- Check 6: order_reviews grain
-- Tests: how many review rows, distinct orders and distinct review_id values are there?
-- Found: 99,224 rows cover 98,673 distinct orders and 98,410 distinct review_id values.
-- Compared with 99,441 total orders, 768 orders have no review.
-- 551 extra rows (99,224 - 98,673) come from orders with more than one review.
select count(*) as total_rows,
       count(distinct order_id) as unique_orders,
       count(distinct review_id) as unique_review_ids
from order_reviews;

-- Check 6b: orders with more than one review
-- Tests: how many orders have multiple review rows, and how many extra rows do they create?
-- Found: 547 orders have multiple reviews, creating 551 extra rows.
select count(*) as orders_with_multiple_reviews,
       sum(review_rows - 1) as extra_rows
from (
    select order_id, count(*) as review_rows
    from order_reviews
    group by order_id
    having count(*) > 1
) as t;

-- Check 7: repeated review_id values
-- Tests: how many review_id values appear more than once, and how many extra rows do they create?
-- Found: 789 review_id values are repeated, creating 814 extra rows (99,224 - 98,410).
-- review_id alone is therefore not a unique key. See Check 17 for the key that works.
select count(*) as repeated_review_ids,
       sum(times_used - 1) as extra_rows
from (
    select review_id, count(*) as times_used
    from order_reviews
    group by review_id
    having count(*) > 1
) as t;

-- Check 8: order status mix
-- Tests: how many orders are in each order status?
-- Found: 8 statuses. delivered 96,478, shipped 1,107, canceled 625, unavailable 609,
-- invoiced 314, processing 301, created 5, approved 2 (total 99,441).
-- This list drives which statuses count as revenue (DECISIONS.md entry 6).
select
	order_status,
	count(*) as total_count
from
	orders
group by
	order_status
order by
	total_count desc;

-- Check 9: order date range
-- Tests: when were the earliest and latest purchases?
-- Found: purchases range from 2016-09-04 21:15:19 to 2018-10-17 17:30:18.
select min(order_purchase_timestamp) as min_time,
       max(order_purchase_timestamp) as max_time
from orders;

-- Check 10: monthly order trend
-- Tests: how many orders were purchased in each month, and which months are too thin for trends?
-- Found: Sep 2016 has 4 orders, Nov 2016 has no orders at all, Oct 2018 has 4 orders.
-- Other thin months: Dec 2016 with 1 order and Sep 2018 with 16 orders.
-- The peak is November 2017 with 7,544 orders.
-- Trend questions (Q1, Q7, Q8) must exclude the partial edge months (DECISIONS.md entry 6).
select date_trunc('month', order_purchase_timestamp) as month,
       count(order_id) as total_orders
from orders
group by month
order by month;

-- Check 11: missing items by order status
-- Tests: which statuses account for orders with no row in order_items?
-- Found: 775 orders have no item row: unavailable 603, canceled 164, created 5, invoiced 2, shipped 1.
-- 767 of the 775 are unavailable or canceled, so they are not real sales.
-- Created and invoiced orders are early in the process, so no items yet is believable.
-- The 1 shipped order with no items is a small data inconsistency.
select o.order_status, count(*) as orders_without_items
from orders o
left join order_items i on o.order_id = i.order_id
where i.order_id is null
group by o.order_status
order by orders_without_items desc;

-- Check 12: orders missing payments
-- Tests: which orders have no row in order_payments, and what is their status?
-- Found: 1 of 99,441 orders has no payment row. Its status: delivered.
select o.order_status, count(*) as orders_without_payments
from orders o
left join order_payments p on o.order_id = p.order_id
where p.order_id is null
group by o.order_status;

-- Check 13: orders missing reviews
-- Tests: how many orders have no row in order_reviews?
-- Found: 768 of 99,441 orders have no review row.
-- A missing review means no recorded survey response, not a low or high score.
select count(*) as orders_without_reviews
from orders o
left join order_reviews r on o.order_id = r.order_id
where r.order_id is null;

-- Check 14: missing product categories
-- Tests: how many products have no category name?
-- Found: 610 products have a null product_category_name.
select count(*) as products_without_category
from products
where product_category_name is null;

-- Check 15: categories missing translations
-- Tests: which non-null product categories have no row in category_translation, and how many products use them?
-- Found: pc_gamer and portateis_cozinha_e_preparadores_de_alimentos have no English translation.
-- Products affected: 13.
-- Q2 needs a fallback label for these and for the 610 products with no category (Check 14).
select p.product_category_name, count(*) as products
from products p
left join category_translation ct on p.product_category_name = ct.product_category_name
where ct.product_category_name is null
  and p.product_category_name is not null
group by p.product_category_name;

-- Check 16: missing dates on delivered orders
-- Tests: which fulfillment timestamps are missing among orders marked delivered, and do the gaps overlap?
-- Found: of 96,478 delivered orders, 14 have no approval date, 2 have no carrier date and 8 have no customer delivery date.
-- Orders missing at least one of the three: 47. If this is less than 24, the gaps overlap.
-- Q4 and Q5 only need the customer delivery date, so they filter on it being not null (DECISIONS.md entry 5).
select count(*) as delivered_orders,
       count(*) filter (where order_approved_at is null) as no_approved_date,
       count(*) filter (where order_delivered_carrier_date is null) as no_carrier_date,
       count(*) filter (where order_delivered_customer_date is null) as no_customer_date,
       count(*) filter (where order_approved_at is null
                           or order_delivered_carrier_date is null
                           or order_delivered_customer_date is null) as missing_any
from orders
where order_status = 'delivered';

-- Check 17: is review_id + order_id a unique key?
-- Tests: does the number of distinct (review_id, order_id) pairs equal the number of rows?
-- Found: all 99,224 rows are distinct pairs, so review_id + order_id is unique.
-- Repeated review_id values still occur, on different orders.
select count(*) as total_rows,
       (select count(*) from (select distinct review_id, order_id from order_reviews) d) as distinct_pairs
from order_reviews;

-- Check 18: do repeated review_id values belong to the same person?
-- Tests: among repeated review_id values, how many span more than one customer_unique_id?
-- Found: 0. If 0, every repeated review_id belongs to one person who placed
-- several orders at close times and reviewed them together (DECISIONS.md entry 8).
select count(*) as repeated_ids_spanning_multiple_people
from (
    select r.review_id
    from order_reviews r
    join orders o on r.order_id = o.order_id
    join customers c on o.customer_id = c.customer_id
    where r.review_id in (
        select review_id from order_reviews group by review_id having count(*) > 1
    )
    group by r.review_id
    having count(distinct c.customer_unique_id) > 1
) as t;

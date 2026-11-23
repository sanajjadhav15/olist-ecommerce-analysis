-- Purpose: sanity checks before any analysis

-- Check 1: customers
-- Tests: is customer_id unique per row, and how does it compare to customer_unique_id?
-- Found: 99,441 rows and 99,441 distinct customer_id values, but only 96,096 distinct customer_unique_id values.
-- Customer_id is not a person-level key: it is the customer identifier assigned to each order.
-- Use customer_unique_id for person-level counts and customer_id only for joins.
select COUNT(*) as total_rows, COUNT(distinct customer_id) as unique_customer, COUNT(distinct customer_unique_id) as unique_people from customers;

-- Check 2: order_items grain
-- Tests: how many orders exist in order_items, and do items have a one-row-per-order grain?
-- Found: 112,650 item rows represent 98,666 distinct orders.
-- This table is one row per item, not one row per order. COUNT(*) counts units/items, not orders.
select COUNT(*) as total_rows, COUNT(distinct order_id) as unique_orders from order_items;

-- Check 3: largest orders
-- Tests: what is the maximum number of items in an order?
-- Found: the largest order has 21 rows/items. The next-largest orders have 20, 20, 15, and 15 rows/items.
select COUNT(*) as total_items, order_id from order_items
group by order_id
order by total_items desc
limit 5;

-- Check 4: multi-item orders
-- Tests: how many orders contain more than one item row?
-- Found: 9,803 orders, or about 9.9% of orders in order_items, contain more than one item.
-- The dataset has no quantity column, so repeated item rows represent separate units or product lines.
select count(*) from (
select count(*) as total_items from order_items
group by order_id
having count(*)>1
) as t;

-- Check 5: order_payments grain
-- Tests: how many payment rows and distinct orders are in the payments table?
-- Found: 103,886 rows cover 99,440 of the 99,441 orders. One order has no payment row.
-- Split payments create several rows per order, so payments must be aggregated before joining to the order grain.
select count(*) as total_rows, count(distinct order_id) as unique_orders from order_payments op;

-- Check 6: order_reviews grain
-- Tests: how many review rows, orders, and review IDs are present?
-- Found: 99,224 rows cover 98,673 distinct orders and 98,410 distinct review_id values.
-- Compared with 99,441 total orders, 768 orders have no review. 547 orders have multiple review rows, creating 551 extra rows.
select count(*) as total_rows, count(distinct order_id) as unique_orders, count(distinct review_id) as unique_reviews from order_reviews t;

-- Check 7: repeated review_id values
-- Tests: do any review_id values appear more than once, indicating duplicate or reused review records?
-- Found: 789 distinct review_id values are repeated, accounting for 814 extra review rows.
-- Reusing this column as a unique key would therefore be incorrect. Aggregate or filter reviews carefully before joining.
select count(*) as total_items, review_id from order_reviews
group by review_id
having count(*)>1;

-- Check 8: order status mix
-- Tests: how many orders are in each order status?
-- Found: most orders are delivered (96,478). Shipped (1,107) and canceled (625) are the next largest statuses.
select order_status, count(*) as total_count from orders o 
group by order_status
order by total_count desc;

-- Check 9: order date range
-- Tests: when did the earliest and latest purchases occur?
-- Found: purchases range from 2016-09-04 21:15:19 to 2018-10-17 17:30:18.
select min(order_purchase_timestamp) as min_time, max(order_purchase_timestamp) as max_time from orders;

-- Check 10: monthly order trend
-- Tests: how many orders were purchased in each month?
-- Found: activity starts at low levels in 2016 and peaks in November 2017 with 7,544 orders.
-- Month is truncated from the purchase timestamp, so orders are grouped by calendar month.
select date_trunc('month', order_purchase_timestamp) as month, count(order_id) as total_orders from orders
group by month
order by month;

-- Check 11: orders missing item rows
-- Tests: are there any orders with no matching row in order_items?
-- Found: 775 of 99,441 orders have no item row.
select count(*) from orders o 
left join order_items oi 
on o.order_id=oi.order_id
where oi.order_id is null;

-- Check 12: missing items by order status
-- Tests: which statuses account for orders that have no item row?
-- Found: unavailable orders account for 603 missing-item cases, followed by canceled (164), created (5), invoiced (2), and shipped (1).
-- These missing rows are concentrated in statuses that may not represent completed purchases.
select o.order_status, count(*) as orders_without_items
from orders o
left join order_items i on o.order_id = i.order_id
where i.order_id is null
group by o.order_status
order by orders_without_items desc;

-- Check 13: orders missing payments
-- Tests: are there orders with no matching payment row?
-- Found: 1 of 99,441 orders has no payment row.
select count(*) from orders o 
left join order_payments op
on o.order_id=op.order_id
where op.order_id is null;

-- Check 14: orders missing reviews
-- Tests: are there orders with no matching review row?
-- Found: 768 of 99,441 orders have no review row.
-- A missing review should be treated as no recorded survey response, not necessarily a low or high score.
select count(*) from orders o 
left join order_reviews t  
on o.order_id=t.order_id
where t.order_id is null;

-- Check 15: missing items by status
-- Tests: repeat the missing-item check using status and a direct group-by join.
-- Found: unavailable has 603, canceled 164, created 5, invoiced 2, and shipped 1 order without item rows.
select o.order_status, count(*) from orders o 
left join order_items oi 
on o.order_id=oi.order_id
where oi.order_id is null 
group by o.order_status;

-- Check 16: delivered orders with no customer delivery date
-- Tests: does every order marked delivered include a customer delivery timestamp?
-- Found: 8 of 96,478 delivered orders have no order_delivered_customer_date.
select count(*) from orders o 
where order_status = 'delivered' and o.order_delivered_customer_date is null;

-- Check 17: missing product categories
-- Tests: how many products have no category name?
-- Found: 610 products have a null product_category_name.
select count(*) from products p 
where p.product_category_name is null;

-- Check 18: categories missing translations
-- Tests: which non-null product categories have no matching row in category_translation?
-- Found: pc_gamer and portateis_cozinha_e_preparadores_de_alimentos have no English-category translation.
-- These categories may need a fallback label or may remain untranslated in category analysis.
select distinct p.product_category_name from products p 
left join category_translation ct 
on p.product_category_name=ct.product_category_name
where ct.product_category_name is null;

-- Check 19: incomplete dates for delivered orders
-- Tests: which key fulfillment timestamps are missing among orders marked delivered?
-- Found: 96,478 delivered orders have 14 missing approval dates, 2 missing carrier dates, and 8 missing customer delivery dates.
-- These counts overlap because some records can be missing multiple timestamps.
select
  count(*) as delivered_orders,
  count(*) filter (where order_approved_at is null) as no_approved_date,
  count(*) filter (where order_delivered_carrier_date is null) as no_carrier_date,
  count(*) filter (where order_delivered_customer_date is null) as no_customer_date
from orders
where order_status = 'delivered';

-- Check 20: review row and review-order pair counts
-- Tests: whether review_id plus order_id forms the full number of distinct review pairs.
-- Found: all 99,224 review rows are distinct review_id/order_id pairs, so this check finds no exact duplicate pair.
-- Repeated review_id values can still belong to different orders.
select count(*) as total_rows,
       (select count(*) from (select distinct review_id, order_id from order_reviews) d) as distinct_pairs
from order_reviews;

-- Check 21: repeated review IDs and their orders
-- Tests: inspect 20 repeated review_id values and the orders associated with them.
-- Found: repeated review IDs occur across different orders rather than as exact duplicate review_id/order_id pairs.
-- This helps distinguish duplicated row IDs from legitimate separate review records on multiple orders.
select r.review_id, r.order_id, r.review_score, r.review_creation_date,
       o.customer_id, o.order_purchase_timestamp
from order_reviews r
join orders o on r.order_id = o.order_id
where r.review_id in (
    select review_id from order_reviews group by review_id having count(*) > 1
)
order by r.review_id, r.order_id
limit 20;

-- Check 22: repeated reviews across orders and customers
-- Tests: for repeated review IDs, how many distinct orders and customer people are involved?
-- Found: this summarizes repeated review IDs by order and customer reach, ordered to show IDs tied to the most orders first.
-- Repeated IDs should not be counted as 1-to-1 review records unless the intended grain is explicitly review_id.
select r.review_id,
       count(distinct r.order_id) as orders,
       count(distinct c.customer_unique_id) as people
from order_reviews r
join orders o on r.order_id = o.order_id
join customers c on o.customer_id = c.customer_id
where r.review_id in (
    select review_id from order_reviews group by review_id having count(*) > 1
)
group by r.review_id
order by orders desc
limit 20;
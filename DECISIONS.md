# DECISIONS.md

A log of data problems I found and the choices I made.

## 1. Revenue means seller sales, not Olist revenue
- **Saw:** order_items has price and freight_value, but no column for Olist's commission.
- **Problem:** I cannot calculate Olist's own revenue, so calling it "revenue" without a definition would mislead.
- **Options:** (a) call it Olist revenue, (b) define it as seller sales and state that.
- **Chose:** (b). Revenue = sum of item price (seller sales). Freight is reported separately, not mixed in, because it pays for shipping and is not the value of the product. I will state this in the README.

## 2. customer_id vs customer_unique_id
- **Saw:** customers has 99,441 rows and 99,441 distinct customer_id, but only 96,096 distinct customer_unique_id.
- **Problem:** customer_id is created per order, so counting it as "customers" would treat repeat buyers as new people. The gap (3,345) is orders placed by people who had ordered before.
- **Options:** use either column, or use customer_unique_id for people.
- **Chose:** customer_unique_id for anything about people (Q6, Q7, Q9). customer_id only as the join key from orders to customers.

## 3. Grain of order_items, order_payments and order_reviews
- **Saw:**
  - order_items: 112,650 rows, 98,666 distinct orders. 9,803 orders (about 9.9%) have more than one item, max 21. No quantity column: 3 units means 3 rows.
  - order_payments: 103,886 rows, 99,440 distinct orders. Split payments (for example voucher plus card) create several rows per order.
  - order_reviews: 99,224 rows, 98,673 distinct order_id, 98,410 distinct review_id. Some orders have several reviews.
  - Orders with no match: 775 with no items (603 unavailable, 164 canceled, 5 created, 2 invoiced, 1 shipped), 1 with no payment row, 768 with no review.
- **Problem:** joining these tables directly to orders multiplies rows unevenly (only multi-row orders are inflated), so order-level totals would be wrong. Inner joins also silently drop orders with no match.
- **Options:** join directly and fix later, or aggregate each table to one row per order first.
- **Chose:** aggregate to order level before joining, start from orders with LEFT JOIN where orders with no match matter, and compare COUNT(*) before and after every join. Sum a column only if its own table has not been multiplied by another join. Grain: order_items = order_id + order_item_id, order_payments = order_id + payment_sequential, order_reviews = review_id + order_id.

## 4. A review does not mean the order was delivered
- **Saw:** the dataset description says the survey is sent on delivery or when the estimated date passes, whichever is first.
- **Problem:** I had assumed a review implies delivery, which is false.
- **Options:** treat all reviews equally, or restrict delivery analysis to delivered orders with a delivered date.
- **Chose:** for Q4 and Q5, use only delivered orders with a delivered date.

## 5. Delivered orders with missing dates
- **Saw:** among 96,478 delivered orders, 8 have no order_delivered_customer_date, 14 have no approved date, and 2 have no carrier date.
- **Problem:** delivery days and lateness cannot be calculated without the customer date, and a status filter alone would let those rows in.
- **Options:** keep them and get NULLs, or filter on the date being not null.
- **Chose:** filter on order_delivered_customer_date is not null (excludes 8) for Q4 and Q5. Approved and carrier dates are not used there, so those gaps do not matter unless I later split delays into seller time and carrier time.

## 6. Order statuses and thin months
- **Saw:** 8 statuses: delivered 96,478, shipped 1,107, canceled 625, unavailable 609, invoiced 314, processing 301, created 5, approved 2. Data runs from 2016-09 to 2018-10. Sep 2016 has 4 orders, Oct 2016 324, Nov 2016 none, Dec 2016 1, Sep 2018 16, Oct 2018 4.
- **Problem:** canceled and unavailable orders are not real sales. Thin months show fake growth or decline. LAG compares with the previous row, not the previous calendar month, so a gap in the series makes the growth figure meaningless.
- **Options:** (a) include all statuses, (b) delivered only, (c) exclude only canceled and unavailable. For months: keep everything, drop only empty months, or use a minimum-orders rule and a contiguous series.
- **Chose:** (c) for revenue questions (Q1, Q2, Q3), because shipped, invoiced and processing orders are real sales in progress and the 775 orders with no items add no revenue anyway. For trend questions (Q1, Q7, Q8), use only months with at least 100 orders and keep the series contiguous: Jan 2017 to Aug 2018. Oct 2016 is excluded because Nov and Dec 2016 break the series. Delivery questions (Q4, Q5) use a separate rule: delivered with a delivered date (entry 5).

## 7. Duplicate reviews per order
- **Saw:** 551 extra review rows because some orders have more than one review.
- **Problem:** joining reviews directly would duplicate those orders in Q5 and distort average scores.
- **Options:** keep the latest, keep the earliest, or average the scores.
- **Chose:** keep the latest review per order by review_creation_date, with review_answer_timestamp as the tie-breaker (ROW_NUMBER, rn = 1), because the latest reflects the customer's final opinion. Averaging would create scores that nobody actually gave.

## 8. review_id repeats across different orders
- **Saw:** 814 extra rows because some review_id values appear more than once. The pair review_id + order_id is unique. The repeated IDs sit on different orders placed by the same person (same customer_unique_id) at close purchase times, with the same score.
- **Problem:** review_id alone is not a key. Treating it as unique would undercount reviews or break joins.
- **Options:** deduplicate on review_id, or deduplicate per order_id.
- **Chose:** deduplicate per order_id (entry 7), since Q5 analyses orders. Each of those orders did receive that review, so keeping the review on each order is consistent. The limitation: one review may cover several orders, so those orders are not fully independent observations.
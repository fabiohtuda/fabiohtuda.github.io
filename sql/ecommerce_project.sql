/* 
Exploratory Data Analysis in SQL

1) A Sales Manager needs to understand the trends and identify any significant changes in sales. Calculate a sales performance report quarter over quarter.
2) To design better distribution plans for the year 2018, the team need to identify the performance and percentage of each product to the overall sales during the year 2017 
3) The stakeholders are interested in a Pareto analysis to determine which products are driving the majority of the results. Identify the top products that contribute to 80% of the sales?
4) To evaluate the efficiency in order fulfillment, the team needs to identify the average lead time for each stage from purchasing to delivery.
5) Which percentange of the orders were delivered on time?
6) Which are the customers' preferred payment methods?

7) Calculate the average and median price per customer?  

8) To enhance target marketing and logistics planning, the operations teams needs to understand where the main customers are located. 
9) To focus on building and maintaining strong relationships with the key suppliers, the team needs to identify the states where the main customers are located.
10) How is the current status of each order the operation? The idea is to identify any bottenecks and streamline processes to ensure efficient order management.

Covered topics: 
- Data Manipulation: SELECT statements, JOIN operations, subqueries, aggregation (sum,count,having,avg), SORTING and LIMIT
(colocar um ranking)
- Data Transformation: CAST, CONVERT, CONCAT, SUBSTRING, REPLACE, DATEDIFF, DATEADD, FORMAT, CASE statements, NULL handling (isnull, nullif, coalesce)
- Data Analysis: include examples that showcase your ability to perform calculations, generate insights and derive meaning information from the data. 
ROW_NUMBER, RANK, LAG, LEAD / Data Aggregation (grouping sets, rollup, cube) / CTE / Data Filtering and conditional analysis / Statistical functions (avg, sum, stddev, etc)
- Data Visualization: 
--creating views that encapsulate complex queries for easier acess and reporting
--pivot tables
--stored procedures
--extracting insights
*/

-- 1) A Sales Manager needs to understand the trends and identify any significant changes in sales. Calculate a sales performance report quarter over quarter.

-- Analyzing the quantity of orders in each year and month
SELECT 
	DATE(DATE_TRUNC('month', order_purchase_timestamp)) AS purchase_year, 
	COUNT(*) AS orders
FROM olist_orders
GROUP BY 1
ORDER BY 1 DESC

-- We do not have a fully olist_orders data from years 2016, 2017 and 2018. In that way, we will perform a quarterly sales performance from 2016-10-01 until 2018-09-01


-- As known that each order_id can contain multiple products, we used a CTE to aggregate at order_id level by total products, price and freight value
WITH aggregate_order_items AS(

SELECT 
	order_id, 
	SUM(order_item_id) AS items, 
	COUNT(product_id) AS products,
	SUM(price) AS price,
	SUM(freight_value) AS freight_value,
	SUM(price + freight_value) AS total_price
FROM olist_order_items
GROUP BY 1
),

quarterly_sales AS(
	
SELECT 
	DATE(DATE_TRUNC('quarter', o.order_purchase_timestamp)) AS year_quarter,
	SUM(aoi.items) AS items,
	SUM(aoi.total_price) AS total_price
FROM olist_orders o 
LEFT JOIN aggregate_order_items aoi ON o.order_id = aoi.order_id
GROUP BY 1
)

SELECT 
	year_quarter, 
	total_price,
	LAG(total_price) OVER( ORDER BY year_quarter) AS previous_quarterly_sales,
	total_price / NULLIF(LAG(total_price) OVER( ORDER BY year_quarter),0) AS QoQ_pct -- handling division by zero using nullif
FROM quarterly_sales 
WHERE year_quarter>='2017-01-01' AND year_quarter<='2018-09-01' -- filtering only fully quarters for comparison
ORDER BY 1

--2) To design better distribution plans for the year 2018, the team need to identify the performance and percentage of each product to the overall sales during the year 2017 

WITH product_categories_english AS( --aggregating at product category level

SELECT 
	i.order_id,
	i.product_id, 
	t.product_category_name_english, 
	SUM(i.price) AS price, 
	SUM(i.freight_value) freight_value,
	SUM(i.price + i.freight_value) AS total_price
FROM olist_order_items i
LEFT JOIN olist_products p ON i.product_id = p.product_id
LEFT JOIN olist_product_category_name_translation t ON t.product_category_name = p.product_category_name
GROUP BY 1,2,3
)

SELECT product_category, ROUND( total_price / SUM(total_price) OVER(),3) AS total_price_percent
FROM(
	SELECT  
		c.product_category_name_english AS product_category, 
		SUM(c.total_price) AS total_price
	FROM product_categories_english c
	LEFT JOIN olist_orders o ON o.order_id = c.order_id
	WHERE 
		order_approved_at IS not NULL --filtering only both sent and approved orders for sales reporting
		AND DATE(DATE_TRUNC('year', o.order_approved_at))='2017-01-01'
	GROUP BY 1
) sub

ORDER BY 2 DESC

/*
3) The stakeholders are interested in a Pareto analysis to determine which products are driving the majority of the results. Identify the top products that contribute to 80% of the sales?
*/

WITH product_categories_english AS( --aggregating at product category level

SELECT 
	i.order_id,
	i.product_id, 
	t.product_category_name_english, 
	SUM(i.price) AS price, 
	SUM(i.freight_value) freight_value,
	SUM(i.price + i.freight_value) AS total_price
FROM olist_order_items i
LEFT JOIN olist_products p ON i.product_id = p.product_id
LEFT JOIN olist_product_category_name_translation t ON t.product_category_name = p.product_category_name
GROUP BY 1,2,3
),

product_category_agg AS(
	
	SELECT 
		COALESCE(product_category, 'without_category') AS product_category, --handling missing value at product category level
		ROUND( 100 *(total_price / SUM(total_price) OVER() ) ,3) AS total_sales_pct

	FROM(
			SELECT  
					c.product_category_name_english AS product_category, 
					SUM(c.total_price) AS total_price
			FROM product_categories_english c
			LEFT JOIN olist_orders o ON o.order_id = c.order_id
			WHERE 
				order_approved_at IS not NULL --filtering only both sent and approved orders for sales reporting
				AND DATE(DATE_TRUNC('year', o.order_approved_at))='2017-01-01'
			GROUP BY 1
	) sub
	ORDER BY 2 DESC
)

--Performing SUM OVER to find out the accumulative percentage from each product category
SELECT 
	product_category,
	SUM(total_sales_pct) OVER( ORDER BY total_sales_pct DESC) AS total_sales_running_sum
FROM product_category_agg

--In 2017, approximmately 80% of sales were driven from 16 categories.

--4) To evaluate the efficiency in order fulfillment, the team needs to identify the average lead time for each stage from purchasing to delivery.
WITH delivery_time AS(

SELECT 
	order_id,
	customer_id,
	DATE_PART('day', order_approved_at - order_purchase_timestamp ) AS purchase_to_approval,
	DATE_PART('day', order_delivered_carrier_date - order_approved_at) AS approval_to_carrier,
	DATE_PART('day', order_delivered_customer_date - order_delivered_carrier_date) AS carrier_to_customer,
	DATE_PART('day', order_delivered_customer_date - order_purchase_timestamp) AS total_lead_time,
	CASE WHEN DATE(order_delivered_customer_date) <= DATE(order_estimated_delivery_date) THEN TRUE ELSE FALSE END AS delivered_on_time,
	DATE_PART('day', order_estimated_delivery_date - order_delivered_customer_date) AS delivery_date_delta
FROM olist_orders
WHERE 
	order_status = 'delivered'
)

SELECT 
	ROUND(AVG(purchase_to_approval)::NUMERIC,2) AS purchase_to_approval_avg,
	ROUND(AVG(approval_to_carrier) ::NUMERIC,2) AS approval_to_carrier_avg,
	ROUND(AVG(carrier_to_customer) ::NUMERIC,2) AS carrier_to_customer_avg,
	ROUND(AVG(total_lead_time)::NUMERIC,2) AS total_lead_time_avg,
	ROUND(AVG(delivery_date_delta) ::NUMERIC,2)AS delivery_date_delta_avg
FROM delivery_time



--5) Which percentange of the orders were delivered on time?
WITH delivery_time AS(

SELECT 
	order_id,
	customer_id,
	DATE_PART('day', order_approved_at - order_purchase_timestamp ) AS purchase_to_approval,
	DATE_PART('day', order_delivered_carrier_date - order_approved_at) AS approval_to_carrier,
	DATE_PART('day', order_delivered_customer_date - order_delivered_carrier_date) AS carrier_to_customer,
	DATE_PART('day', order_delivered_customer_date - order_purchase_timestamp) AS total_lead_time,
	CASE WHEN DATE(order_delivered_customer_date) <= DATE(order_estimated_delivery_date) THEN TRUE ELSE FALSE END AS delivered_on_time,
	DATE_PART('day', order_estimated_delivery_date - order_delivered_customer_date) AS delivery_date_delta
FROM olist_orders
WHERE 
	order_status = 'delivered'
)

SELECT 
	delivered_on_time, 
	COUNT(DISTINCT order_id) AS orders,
	AVG(delivery_date_delta) AS avg_delay
FROM delivery_time
GROUP BY 1	

/* 7% of the orders were delivery with delay, with an average of 10.62 days */


--6) Which are the customers' preferred payment methods?

WITH orders_base AS(
	
SELECT 
	o.order_id, 
	o.order_approved_at,
	p.payment_type,
	COUNT(i.order_id) AS orders,
	SUM(i.price) price, 
	SUM(i.freight_value) freight_value,
	SUM(i.price + i.freight_value) AS total_price,
	p.payment_value,
	p.payment_installments
FROM olist_orders o
LEFT JOIN olist_order_items    i ON o.order_id = i.order_id
LEFT JOIN olist_order_payments p ON o.order_id = p.order_id
WHERE 
	o.order_approved_at IS NOT NULL 
	AND p.payment_type IS NOT NULL
GROUP BY 1,2,3,8,9
)

SELECT 
	payment_type, 
	purchases, 
	ROUND(purchases / SUM(purchases) OVER(),2) AS payment_type_pct
FROM(

	SELECT 
		payment_type, 
		COUNT(order_id) AS purchases
	FROM orders_base
	GROUP BY 1
) sub
ORDER BY 2 DESC
 
--in this dataset ranging from 2016-oct until nov 2018, 74% of the payments were realized by credit_card, followed by 19% of boleto (invoice).

--7) Which is the price distribution for the entire dataset? Which is the average and median total price?  

WITH product_categories_english AS( --aggregating at product category level

SELECT 
	i.order_id,
	i.product_id, 
	t.product_category_name_english, 
	SUM(i.price) AS price, 
	SUM(i.freight_value) freight_value,
	SUM(i.price + i.freight_value) AS total_price
FROM olist_order_items i
LEFT JOIN olist_products p ON i.product_id = p.product_id
LEFT JOIN olist_product_category_name_translation t ON t.product_category_name = p.product_category_name
GROUP BY 1,2,3
)

--Analyzing the distribution of the dataset
SELECT 
	FLOOR(total_price/5)*5 AS bin_size, 
	COUNT(*)
FROM product_categories_english
GROUP BY 1
ORDER BY 1 

--The majority of purchasing prices are located ranging betwewn 1-500. 
--Let's breakdown within these ranges:
SELECT 
	total_price_ranges, 
	SUM(purchases) AS purchases, 
	ROUND( SUM(purchases) / SUM(purchases) OVER() ,2) AS price_ranges_pct 
FROM(
		SELECT 
			CASE WHEN total_price <50 THEN  '1. less than 50'
				 WHEN total_price <100 THEN '2. between 50- 99'
				 WHEN total_price <150 THEN '3. between 100-149'
				 WHEN total_price <200 THEN '4. between 150-199'
				 WHEN total_price <300 THEN '5. between 200-299'
				 WHEN total_price <400 THEN '6. between 300-399'
				 WHEN total_price <500 THEN '7. between 400-499'
				 WHEN total_price <600 THEN '8. between 500-599'
				 ELSE '9. more than 500'
			END AS total_price_ranges,
			COUNT(*) AS purchases
		FROM product_categories_english
		GROUP BY 1
		ORDER BY 1 
) sub
GROUP BY total_price_ranges, purchases
ORDER BY total_price_ranges

--8) To enhance target marketing and logistics planning, the operations teams needs to understand where the main customres are located. 

WITH orders_prices AS(

	SELECT 
		i.order_id,
		SUM(i.price) AS price, 
		SUM(i.freight_value) freight_value,
		SUM(i.price + i.freight_value) AS total_price
	FROM olist_order_items i
	GROUP BY 1
),

customers_agg AS(

	SELECT  
		c.customer_state, 
		COUNT(DISTINCT o.customer_id) AS unique_customers,
		SUM(op.total_price) AS total_price
	FROM olist_orders o 
	LEFT JOIN olist_customers c ON o.customer_id = c.customer_id
	LEFT JOIN orders_prices op ON o.order_id = op.order_id
	WHERE 
		order_approved_at IS NOT NULL 
	GROUP BY 1
	ORDER BY 2 DESC
)

SELECT 
	customer_state, 
	unique_customers,
	ROUND( unique_customers / NULLIF(SUM(unique_customers) OVER(),0),2) AS customers_pct,
	total_price, 
	ROUND( total_price / NULLIF(SUM(total_price) OVER(),0),2) AS total_price_pct
FROM customers_agg

/*
The majority of the customers' states were mainly located in the following states:
1) Sao Paulo, accountable with 42% customers and 37% of revenue 
2) Rio de Janeiro (RJ)    - 13% share of customers and 13% share of revenue 
3) Minas Gerais (MG)      - 12% share of customers and 12% share of revenue  
4) Rio Grande do Sul (RS) -  5% share of customers and  6% share of revenue
5) Parana (PR)            -  5% share of customers and  5% share of revenue

- The growth marketing and logistics planning should consider these states for the following years
- According to IBGE, the top 5 states in terms of population were Sao Paulo (22.2%), Minas Gerais (10%), Rio de Janeiro (8%), Bahia (7.1%), Parana (5.7%)
- Besides MG was 2nd in terms of population, they are in 3rd position, responsible for 12% share of revenue. Are the marketing campaigns for this state being effective? This occurs in the Bahia state as well.
*/

--9) To focus on building and maintaining strong relationships with the key suppliers, the team needs to identify the states where the main customers are located.

WITH orders_prices AS(

	SELECT 
		i.order_id,
		SUM(i.price) AS price, 
		SUM(i.freight_value) freight_value,
		SUM(i.price + i.freight_value) AS total_price
	FROM olist_order_items i
	GROUP BY 1
),

customers_agg AS(

	SELECT  
		c.customer_state, 
		COUNT(DISTINCT o.customer_id) AS unique_customers,
		SUM(op.total_price) AS total_price
	FROM olist_orders o 
	LEFT JOIN olist_customers c ON o.customer_id = c.customer_id
	LEFT JOIN orders_prices op ON o.order_id = op.order_id
	WHERE 
		order_approved_at IS NOT NULL 
	GROUP BY 1
	ORDER BY 2 DESC
),

customer_base AS(

	SELECT 
		customer_state, 
		unique_customers,
		ROUND( unique_customers / NULLIF(SUM(unique_customers) OVER(),0),2) AS customers_pct,
		total_price, 
		ROUND( total_price / NULLIF(SUM(total_price) OVER(),0),2) AS total_price_pct
	FROM customers_agg
),

sellers AS(
	
	SELECT  
		s.seller_state,
		COUNT(i.product_id) AS products
	FROM olist_order_items i
	LEFT JOIN olist_sellers s ON i.seller_id = s.seller_id
	GROUP BY 1
),

sellers_database AS(

SELECT 
	seller_state, 
	products, 
	ROUND( products / NULLIF(SUM(products) OVER() ,0) ,2) AS sellers_state_pct
FROM sellers
ORDER BY 3 DESC
)

SELECT 
	cb.customer_state, 
	cb.unique_customers, 
	cb.customers_pct,
	cb.total_price, 
	cb.total_price_pct, 
	COALESCE(sb.products,0) AS products, 
	COALESCE(sb.sellers_state_pct,0) AS sellers_state_pct
FROM customer_base cb 
LEFT JOIN sellers_database sb ON cb.customer_state = sb.seller_state
ORDER BY sb.products DESC NULLS LAST

-- To get an overall perspective between demand and supply, we combined customers CTE and sellers CTE
-- In this summary, we noticed that the sellers are mainly in 8 states, which SP was accountable for 71% of the sellers in this period.
-- Some states, such as TO, AL, AP and RR did not have any sellers in this period.


--10) How is the current status of each order the operation? The idea is to identify any bottenecks and streamline processes to ensure efficient order management.

SELECT 
	order_status, 
	COUNT(order_id) AS orders, 
	COUNT(DISTINCT customer_id) AS unique_customers
FROM olist_orders
WHERE 
	DATE(DATE_TRUNC('month', order_purchase_timestamp)) >= '2018-07-01'
GROUP BY 1


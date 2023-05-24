# Croma customer transactions
select * from fact_sales_monthly 
where customer_code = (
	select customer_code from dim_customer 
	where customer like '%croma%' and market = 'India'
);

# Fiscal year for this company starts from September
# Thus, Sept 2020 is 1st month of 2021 so add 4 months to each month to get fiscal year
# Functions
delimiter //
CREATE FUNCTION get_fiscal_yr (
	calender_date date
) RETURNS INTEGER
deterministic
BEGIN
	declare fiscal_yr int;
    set fiscal_yr = year(date_add(calender_date , interval 4 month)) ;    
RETURN fiscal_yr;
END
//
delimiter ;


# Croma Sales transactions for fiscal year 2021
select * from fact_sales_monthly 
where customer_code = 90002002 and 
	  get_fiscal_yr(date) = 2021
order by date ;

# Q1-9,10,11  Q2-12,1,2   Q3-3,4,5   Q4-6,7,8
# Function creation to get Quarter wise details
delimiter //
create function get_fiscal_quarter(	
	calender_date date
) returns char(2)
deterministic 
begin 
	declare m tinyint ;
    declare qtr char(2) ;
    set m = month(calender_date);
    
    # If else in mysql
    if m in (9,10,11) then set qtr = "Q1" ;  
    elseif m in (12,1,2) then set qtr = "Q2" ;
    elseif m in (3,4,5) then set qtr = "Q3" ;
    else set qtr = "Q4" ;
	end if;
    
    return qtr;
end  //
delimiter ;  

# Sales report of croma for fiscal year 2021 Q4
select * from fact_sales_monthly 
where 
	customer_code = 90002002 and get_fiscal_yr(date) = 2021
    and get_fiscal_quarter(date) = 'Q4'
order by date ;


# Report 
# Month Product Variant Sold_Quantity GrossPrice per Item Gross Total price 
select f.date , f.product_code , p.product , p.variant , f.sold_quantity ,
	   g.gross_price , g.gross_price*f.sold_quantity as Gross_total_price
from 
	fact_sales_monthly f join dim_product p 
    on f.product_code = p.product_code
    join fact_gross_price g 
    on g.product_code = f.product_code and 
	   g.fiscal_year = get_fiscal_yr(f.date)	
where 
	customer_code = 90002002 and get_fiscal_yr(date) = 2021
    and get_fiscal_quarter(date) = 'Q4'
order by date ;

# Report 
/*
The report should have 
1. Month  2. Total gross sales amount to Croma India in this month 
*/
select f.date ,
	   sum(g.gross_price*f.sold_quantity) as Gross_price_total	
	from 
    fact_sales_monthly f join fact_gross_price g
    on f.product_code = g.product_code and 
       g.fiscal_year = get_fiscal_yr(f.date) 
where customer_code = 90002002
group by f.date ;


/*
Generate a yearly report for Croma India where there are two columns
1. Fiscal Year
2. Total Gross Sales amount In that year from Croma
*/
select get_fiscal_yr(f.date) as Fiscal_Year ,
	   sum(g.gross_price*f.sold_quantity) as Gross_price_total	
	from 
    fact_sales_monthly f join fact_gross_price g
    on f.product_code = g.product_code and 
       g.fiscal_year = get_fiscal_yr(f.date) 
where customer_code = 90002002
group by get_fiscal_yr(f.date) 
order by Fiscal_Year ;


# Stored procedure for monthy sales report for any customer
delimiter //
create procedure get_monthly_sales_report(
	c_code int
)
begin 
	select f.date ,
		   sum(g.gross_price*f.sold_quantity) as Gross_price_total	
		from 
		fact_sales_monthly f join fact_gross_price g
		on f.product_code = g.product_code and 
		   g.fiscal_year = get_fiscal_yr(f.date) 
	where customer_code = c_code
	group by f.date ;
end //
delimiter ;

# Execute a stored procedure
call gdb041.get_monthly_sales_report(90002002);
call gdb041.get_monthly_sales_report(70006157);


/*
Create a Stored Procedure that can determine market badget
If total quantity sold is > than 5 million consider gold else silver
Input -> market fiscal_yr
Ouput -> Market badget
*/
delimiter //
create procedure get_market_badget(
	in in_market varchar(45),
    in in_fiscalyr year,
    out market_badget varchar(10)
)
begin
	declare qty int default 0;
    
    # Set default market as India
    if in_market = "" then
		set in_market = "india" ;
	end if ;
    
    # Retrieve total quantity 
    select 
		sum(s.sold_quantity) into qty
    from fact_sales_monthly s join dim_customer c 
	on s.customer_code = c.customer_code
    where get_fiscal_yr(s.date) = in_fiscalyr and c.market = in_market
    group by c.market ;
    
    # Determine Market Badget
    if qty > 5000000 then set market_badget = "Gold" ;
    else set market_badget = "Silver" ;
    end if ;
    
end //
delimiter ;

delimiter //
set @market_badget = '0';
call gdb041.get_market_badget('india', 2021, @market_badget);
select @market_badget; //

set @market_badget = '0';
call gdb041.get_market_badget('indnesia', 2021, @market_badget);
select @market_badget; //
delimiter ;


-- Explain analyze helps us to understand how much time the query takes and 
-- how many steps it goes through to give the result
# Get Total Gross price
explain analyze
select f.date,f.product_code,p.product,p.variant,f.sold_quantity,
	   g.gross_price as gross_price_per_item,
       round(f.sold_quantity * g.gross_price , 2) as gross_price_total,
       pre.pre_invoice_discount_pct
from 
	fact_sales_monthly as f join dim_product as p
    on f.product_code = p.product_code
    join fact_gross_price g
    on f.product_code = g.product_code and get_fiscal_yr(f.date) = g.fiscal_year
    join fact_pre_invoice_deductions pre
    on pre.customer_code = f.customer_code and pre.fiscal_year = get_fiscal_yr(f.date)
where get_fiscal_yr(f.date) = 2021 limit 1000000;

# Thus to improve the query performance, rather than using function for getting 
# fiscal year , we have created a generated column in fact_sales_monthly for fiscal year
select f.date,f.product_code,p.product,p.variant,f.sold_quantity,
	   g.gross_price as gross_price_per_item,
       round(f.sold_quantity * g.gross_price , 2) as gross_price_total,
       pre.pre_invoice_discount_pct
from 
	fact_sales_monthly as f join dim_product as p
    on f.product_code = p.product_code
    join fact_gross_price g
    on f.product_code = g.product_code and f.fiscal_year = g.fiscal_year
    join fact_pre_invoice_deductions pre
    on pre.customer_code = f.customer_code and pre.fiscal_year = f.fiscal_year
where f.fiscal_year = 2021 limit 1000000;

# Get Net invoice sales 
# which is gross_total - (pre_invoice_discount_pct*gross_total)
with x1 as 
	(select f.date,f.product_code,p.product,p.variant,f.sold_quantity,
	   g.gross_price as gross_price_per_item,
       round(f.sold_quantity * g.gross_price , 2) as gross_price_total,
       pre.pre_invoice_discount_pct
	from 
		fact_sales_monthly as f join dim_product as p
		on f.product_code = p.product_code
		join fact_gross_price g
		on f.product_code = g.product_code and f.fiscal_year = g.fiscal_year
		join fact_pre_invoice_deductions pre
		on pre.customer_code = f.customer_code and pre.fiscal_year = f.fiscal_year
	where f.fiscal_year = 2021 limit 1000000 )
select * , gross_price_total - (gross_price_total*pre_invoice_discount_pct) as Net_invoice_sales 
from x1;

-- Views
# Creation of view for Net invoice sales
create or replace view sales_pre_invoice_discount as 
	select f.date,f.fiscal_year,f.customer_code,c.market,
	   f.product_code,p.product,p.variant,f.sold_quantity,
	   g.gross_price as gross_price_per_item,
       round(f.sold_quantity * g.gross_price , 2) as gross_price_total,
       pre.pre_invoice_discount_pct
	from 
		fact_sales_monthly as f join dim_product as p
		on f.product_code = p.product_code
        join dim_customer c 
        on f.customer_code = c.customer_code
		join fact_gross_price g
		on f.product_code = g.product_code and f.fiscal_year = g.fiscal_year
		join fact_pre_invoice_deductions pre
		on pre.customer_code = f.customer_code and pre.fiscal_year = f.fiscal_year ;


select * , 
	gross_price_total - (gross_price_total*pre_invoice_discount_pct) as Net_invoice_sales
from sales_pre_invoice_discount ;

# Creation of View for post_invoice_discount
create view post_invoice_discount as 
	select s.date,s.fiscal_year,s.customer_code,s.market,s.product_code,
           s.product,s.variant,s.sold_quantity,s.gross_price_total,s.pre_invoice_discount_pct,
       (1 - pre_invoice_discount_pct)*gross_price_total as Net_invoice_sales,
       (post.discounts_pct + post.other_deductions_pct) as Post_invoice_discount
	from sales_pre_invoice_discount s join 
		 fact_post_invoice_deductions post
		 on s.date = post.date and s.product_code = post.product_code and 
		 s.customer_code = post.customer_code ;

select * from post_invoice_discount;

# Net Sales
select * , 
       (1-Post_invoice_discount)*Net_invoice_sales as Net_sales
from post_invoice_discount limit 100000;


-- Stored Procedure
# Top n markets by Net Sales
delimiter //
create procedure get_top_n_market_by_net_sales(
	in_fiscal_year int ,
    in_top_n int
)
begin 
	select market , round(sum(net_sales)/1000000 , 2) as Total_Net_Sales 
	from net_sales
	where fiscal_year = in_fiscal_year 
	group by market 
	order by Total_Net_Sales desc
	limit in_top_n;
    
end //
delimiter ;

# Execution of stored procedure
call gdb041.get_top_n_market_by_net_sales(2020, 3);


# Top n customers by Net Sales
delimiter //
create procedure top_n_customer_by_net_sales (
	in_market varchar(45) ,
	in_fiscal_year int ,
    in_top_n int
)
begin 

	select c.customer , round(sum(n.net_sales)/1000000 , 2) as Total_Net_Sales 
	from net_sales n join dim_customer c
	on n.customer_code = c.customer_code
	where n.fiscal_year = in_fiscal_year and n.market = in_market  
	group by c.customer
	order by Total_Net_Sales desc
	limit in_top_n;
    
end //
delimiter ;

# Calling the procedure
call gdb041.top_n_customer_by_net_sales('india', 2021, 3);


# Total Net Sales by product for a particular fiscal year
select 
	product , sum(net_sales) as Total_net_sales
from net_sales where fiscal_year = 2021
group by product 
order by Total_net_sales desc
limit 5 ;


# Getting Net Sales and percentage of contribution of each customer
with x1 as (
select c.customer , round(sum(n.net_sales)/1000000 , 2) as Total_Net_Sales 
from net_sales n join dim_customer c
on n.customer_code = c.customer_code
where n.fiscal_year = 2021  
group by c.customer
)
select 
	* , Total_Net_Sales*100/sum(Total_Net_Sales) over() as pct_contribution 
from x1 
order by Total_Net_Sales desc ;


# Get percentage contribution of customer based on each region
with cte as (
select  c.region , c.customer ,
	   round(sum(n.net_sales)/1000000 , 2) as Total_Net_Sales 
from net_sales n join dim_customer c
on n.customer_code = c.customer_code
where n.fiscal_year = 2021  
group by c.region , c.customer 
)
select 
	* , (Total_Net_Sales*100) / sum(Total_Net_Sales) over(partition by region) as pct 
from cte
order by region , Total_Net_Sales desc;

# line 5 9 6


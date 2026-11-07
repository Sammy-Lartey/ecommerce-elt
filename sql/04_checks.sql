select 'events' as table_name, count(*) as row_count from raw_data.events
union all select 'customers', count(*) from raw_data.customers
union all select 'products', count(*) from raw_data.products;

select sum(net_revenue_usd) as total_revenue_usd from raw_data.events;

select count(*) as blank_regions from raw_data.events where region = '';
select count(*) as na_discount_codes from raw_data.events where discount_code = 'N/A';
select count(*) as refunded from raw_data.events where is_refunded;
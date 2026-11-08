select table_name, ordinal_position, column_name, data_type
from information_schema.columns
where table_schema = 'raw_data'
order by table_name, ordinal_position;

select * from raw_data.events limit 2;
select * from raw_data.customers limit 2;
select * from raw_data.products limit 2;
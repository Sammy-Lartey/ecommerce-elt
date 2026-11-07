-- loads one run from s3 bronze into raw_data
-- deleting the run first means loading the same file twice never doubles the rows
-- everything below runs as one transaction, so a failed copy undoes the delete

delete from raw_data.events where _run_id = '${run_id}';
copy raw_data.events from 's3://sammy-ecom-elt-data/bronze/events/run_id=${run_id}/' iam_role default format as parquet;
insert into ops.load_log (run_id, table_name, source_file, rows_loaded)
select '${run_id}', 'events', max(_source_file), count(*) from raw_data.events where _run_id = '${run_id}';

delete from raw_data.customers where _run_id = '${run_id}';
copy raw_data.customers from 's3://sammy-ecom-elt-data/bronze/customers/run_id=${run_id}/' iam_role default format as parquet;
insert into ops.load_log (run_id, table_name, source_file, rows_loaded)
select '${run_id}', 'customers', max(_source_file), count(*) from raw_data.customers where _run_id = '${run_id}';

delete from raw_data.products where _run_id = '${run_id}';
copy raw_data.products from 's3://sammy-ecom-elt-data/bronze/products/run_id=${run_id}/' iam_role default format as parquet;
insert into ops.load_log (run_id, table_name, source_file, rows_loaded)
select '${run_id}', 'products', max(_source_file), count(*) from raw_data.products where _run_id = '${run_id}';

select table_name, source_file, rows_loaded, loaded_at from ops.load_log where run_id = '${run_id}' order by loaded_at, table_name;
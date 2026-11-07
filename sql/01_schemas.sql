-- schemas for each layer, plus the load log
create schema if not exists raw_data;
create schema if not exists staging;
create schema if not exists marts;
create schema if not exists ops;

create table if not exists ops.load_log (
    run_id varchar(64),
    table_name varchar(50),
    source_file varchar(256),
    rows_loaded bigint,
    loaded_at timestamp default getdate()
);

-- column order matches the parquet files exactly, because COPY maps by position
create table if not exists raw_data.events (
    event_id varchar(32),
    event_type varchar(20),
    event_date timestamp,
    customer_id varchar(20),
    product_id varchar(20),
    country varchar(60),
    latitude double precision,
    longitude double precision,
    region varchar(20),
    channel varchar(40),
    payment_method varchar(40),
    currency varchar(3),
    quantity integer,
    unit_price_local decimal(12,2),
    discount_code varchar(40),
    discount_local decimal(12,2),
    tax_local decimal(12,2),
    net_revenue_local decimal(12,2),
    fx_rate_to_usd decimal(8,4),
    net_revenue_usd decimal(12,2),
    is_refunded boolean,
    refund_datetime timestamp,
    refund_reason varchar(100),
    _run_id varchar(64),
    _source_file varchar(256),
    _ingested_at timestamp
);

create table if not exists raw_data.customers (
    customer_id varchar(20),
    signup_date timestamp,
    region varchar(20),
    currency_preference varchar(3),
    segment varchar(40),
    acquisition_channel varchar(40),
    age_band varchar(20),
    country varchar(60),
    country_latitude double precision,
    country_longitude double precision,
    _run_id varchar(64),
    _source_file varchar(256),
    _ingested_at timestamp
);

create table if not exists raw_data.products (
    product_id varchar(20),
    product_name varchar(200),
    category varchar(60),
    is_subscription boolean,
    billing_cycle varchar(20),
    base_price_usd decimal(12,2),
    first_release_date timestamp,
    vendor varchar(60),
    resale_model varchar(40),
    brand_safe_name varchar(200),
    product_name_orig varchar(200),
    base_price_usd_orig decimal(12,2),
    base_key varchar(120),
    product_version varchar(20),
    _run_id varchar(64),
    _source_file varchar(256),
    _ingested_at timestamp
);

select table_schema, table_name from information_schema.tables where table_schema in ('raw_data', 'ops') order by 1, 2;

with ranked as (
    select
        *,
        row_number() over (partition by product_id order by _ingested_at desc) as rn
    from {{ source('raw_data', 'products') }}
)

select
    product_id,
    {{ clean_text('product_name') }} as product_name,
    {{ clean_text('brand_safe_name') }} as brand_safe_name,
    {{ clean_text('product_name_orig') }} as product_name_orig,
    {{ clean_text('category') }} as category,
    is_subscription,
    {{ clean_text('billing_cycle') }} as billing_cycle,
    base_price_usd,
    base_price_usd_orig,
    first_release_date,
    {{ clean_text('vendor') }} as vendor,
    {{ clean_text('resale_model') }} as resale_model,
    {{ clean_text('base_key') }} as base_key,
    {{ clean_text('product_version') }} as product_version,
    _run_id,
    _ingested_at
from ranked
where rn = 1
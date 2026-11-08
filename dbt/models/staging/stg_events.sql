with ranked as (
    select
        *,
        row_number() over (partition by event_id order by _ingested_at desc) as rn
    from {{ source('raw_data', 'events') }}
)

select
    event_id,
    {{ clean_text('event_type') }} as event_type,
    event_date,
    customer_id,
    product_id,
    {{ clean_text('country') }} as country,
    latitude,
    longitude,
    coalesce(nullif(trim(region), ''), 'North America') as region,
    {{ clean_text('channel') }} as channel,
    {{ clean_text('payment_method') }} as payment_method,
    {{ clean_text('currency') }} as currency,
    quantity,
    unit_price_local,
    {{ clean_text('discount_code') }} as discount_code,
    discount_local,
    tax_local,
    net_revenue_local,
    fx_rate_to_usd,
    net_revenue_usd,
    is_refunded,
    refund_datetime,
    {{ clean_text('refund_reason') }} as refund_reason,
    _run_id,
    _ingested_at
from ranked
where rn = 1
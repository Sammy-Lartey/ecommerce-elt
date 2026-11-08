with ranked as (
    select
        *,
        row_number() over (partition by customer_id order by _ingested_at desc) as rn
    from {{ source('raw_data', 'customers') }}
)

select
    customer_id,
    signup_date,
    coalesce(nullif(trim(region), ''), 'North America') as region,
    {{ clean_text('currency_preference') }} as currency_preference,
    {{ clean_text('segment') }} as segment,
    {{ clean_text('acquisition_channel') }} as acquisition_channel,
    {{ clean_text('age_band') }} as age_band,
    {{ clean_text('country') }} as country,
    country_latitude,
    country_longitude,
    _run_id,
    _ingested_at
from ranked
where rn = 1
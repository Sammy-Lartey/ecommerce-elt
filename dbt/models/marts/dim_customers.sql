select
    customer_id,
    signup_date,
    region,
    country,
    currency_preference,
    segment,
    age_band,
    acquisition_channel
from {{ ref('stg_customers') }}
select
    product_id,
    product_name,
    category,
    is_subscription,
    billing_cycle,
    base_price_usd,
    first_release_date,
    vendor,
    resale_model,
    base_key,
    product_version
from {{ ref('stg_products') }}
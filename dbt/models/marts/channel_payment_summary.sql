select
    channel,
    payment_method,
    count(*) as transactions,
    sum(quantity) as units,
    sum(revenue_usd_incl_tax) as revenue_usd_incl_tax,
    round(avg(revenue_usd_incl_tax), 2) as avg_transaction_value_usd
from {{ ref('fct_transactions') }}
group by channel, payment_method
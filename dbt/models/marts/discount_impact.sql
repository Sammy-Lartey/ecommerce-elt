select
    coalesce(discount_code, 'No discount') as discount_code,
    count(*) as transactions,
    round(avg(quantity), 2) as avg_units_per_transaction,
    round(avg(revenue_usd_incl_tax), 2) as avg_transaction_value_usd,
    sum(discount_usd) as total_discount_usd,
    sum(revenue_usd_incl_tax) as revenue_usd_incl_tax
from {{ ref('fct_transactions') }}
group by coalesce(discount_code, 'No discount')
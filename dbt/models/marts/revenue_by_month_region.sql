select
    event_month,
    region,
    event_type,
    count(*) as transactions,
    sum(quantity) as units,
    sum(revenue_usd_incl_tax) as revenue_usd_incl_tax,
    sum(revenue_usd_ex_tax) as revenue_usd_ex_tax
from {{ ref('fct_transactions') }}
group by event_month, region, event_type
select
    refund_reason,
    count(*) as refunded_transactions,
    sum(revenue_usd_incl_tax) as refunded_revenue_usd
from {{ ref('fct_transactions') }}
where is_refunded
group by refund_reason
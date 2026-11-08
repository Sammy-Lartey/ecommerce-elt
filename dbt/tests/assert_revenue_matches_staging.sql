select *
from (
    select
        (select sum(net_revenue_usd) from {{ ref('stg_events') }}) as silver_total,
        (select sum(revenue_usd_incl_tax) from {{ ref('fct_transactions') }}) as gold_total
)
where abs(silver_total - gold_total) > 0.01
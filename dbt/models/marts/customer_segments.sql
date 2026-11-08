select
    c.segment,
    c.age_band,
    c.acquisition_channel,
    count(distinct t.customer_id) as customers,
    count(*) as transactions,
    sum(t.revenue_usd_incl_tax) as revenue_usd_incl_tax,
    round(sum(t.revenue_usd_incl_tax) / count(distinct t.customer_id), 2) as revenue_per_customer_usd
from {{ ref('fct_transactions') }} t
left join {{ ref('dim_customers') }} c on t.customer_id = c.customer_id
group by c.segment, c.age_band, c.acquisition_channel
select
    p.product_id,
    p.product_name,
    p.category,
    count(*) as transactions,
    sum(t.quantity) as units,
    sum(t.revenue_usd_incl_tax) as revenue_usd_incl_tax,
    sum(t.revenue_usd_ex_tax) as revenue_usd_ex_tax
from {{ ref('fct_transactions') }} t
left join {{ ref('dim_products') }} p on t.product_id = p.product_id
group by p.product_id, p.product_name, p.category
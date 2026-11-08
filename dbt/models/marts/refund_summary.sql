select
    p.product_id,
    p.product_name,
    p.category,
    count(*) as transactions,
    sum(case when t.is_refunded then 1 else 0 end) as refunded_transactions,
    round(1.0 * sum(case when t.is_refunded then 1 else 0 end) / count(*), 4) as refund_rate,
    sum(case when t.is_refunded then t.revenue_usd_incl_tax else 0 end) as refunded_revenue_usd
from {{ ref('fct_transactions') }} t
left join {{ ref('dim_products') }} p on t.product_id = p.product_id
group by p.product_id, p.product_name, p.category
{{ config(
    tags = ['mart', 'finance', 'balances']
) }}

with calendar as (
    -- Extraemos el primer y último día de cada mes transcurrido
    select distinct
        start_of_month,
        end_of_month as month_end_date,
        year_month as year_month_str
    from {{ ref('dim_calendar') }}
    where date_key <= current_date
),

accounts as (
    select distinct
        account_id,
        account_name,
        account_type
    from {{ source('stg', 'dim_account') }}
),

-- 1. Matriz completa de cuentas x meses
account_months as (
    select
        c.start_of_month,
        c.month_end_date,
        c.year_month_str,
        a.account_id,
        a.account_name,
        a.account_type
    from calendar c
    cross join accounts a
),

-- 2. Flujo neto mensual por cuenta (agrupando por el primer día de mes)
monthly_cashflow as (
    select
        year_month, -- Viene como DATE desde int_transactions
        account_id,
        sum(amount) as net_monthly_flow
    from {{ ref('int_transactions') }}
    group by 1, 2
),

-- 3. Cruce con coincidencia exacta de tipo DATE
combined as (
    select
        am.year_month_str as year_month,
        am.month_end_date,
        am.account_id,
        am.account_name,
        am.account_type,
        coalesce(mc.net_monthly_flow, 0) as net_monthly_flow
    from account_months am
    left join monthly_cashflow mc
        on am.start_of_month = mc.year_month
       and am.account_id = mc.account_id
)

-- 4. Cálculo del saldo acumulado temporal
select
    year_month,
    month_end_date,
    account_id,
    account_name,
    account_type,
    net_monthly_flow,
    sum(net_monthly_flow) over (
        partition by account_id 
        order by month_end_date 
        rows between unbounded preceding and current row
    ) as ending_balance
from combined
order by account_id, month_end_date
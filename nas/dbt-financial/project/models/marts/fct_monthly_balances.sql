{{ config(
    tags = ['mart', 'finance', 'balances']
) }}

with calendar as (
    -- Extraer el último día de cada mes directamente de dim_calendar
    select distinct
        year_month,
        end_of_month as month_end_date
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

-- 1. Matriz completa: todas las cuentas en todos los meses
account_months as (
    select
        c.year_month,
        c.month_end_date,
        a.account_id,
        a.account_name,
        a.account_type
    from calendar c
    cross join accounts a
),

-- 2. Flujo neto mensual por cuenta a partir de transacciones intermedias
monthly_cashflow as (
    select
        to_char(transaction_date, 'YYYY-MM') as year_month,
        account_id,
        sum(amount) as net_monthly_flow
    from {{ ref('int_transactions') }}
    group by 1, 2
),

-- 3. Cruzar la matriz con los flujos (los meses sin movimientos devuelven 0)
combined as (
    select
        am.year_month,
        am.month_end_date,
        am.account_id,
        am.account_name,
        am.account_type,
        coalesce(mc.net_monthly_flow, 0) as net_monthly_flow
    from account_months am
    left join monthly_cashflow mc
        on am.year_month = mc.year_month
       and am.account_id = mc.account_id
)

-- 4. Cálculo del saldo acumulado mediante Window Function
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
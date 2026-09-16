{{ config(materialized='view') }}

WITH base AS (
    SELECT
        t.source_hash,
        t.account_id,
        t.value_date AS booking_date,
        t.value_date,
        t.description,
        t.amount,
        t.balance,
        t.source_row_id,
        t.loaded_at,
        a.account_name,
        a.bank,
        a.account_type,
        a.owner AS account_ownership
    FROM {{ ref('stg_cash') }} t
    LEFT JOIN {{ ref('dim_account') }} a
        ON t.account_id = a.account_id
)

SELECT
    -- Identificadores y dimensiones de cuenta
    source_hash,
    account_id,
    account_name,
    bank,
    account_type,
    account_ownership,

    -- Fechas
    booking_date,
    value_date,

    -- Transacción
    description,
    amount,
    amount AS personal_amount,
    balance,

    -- Clasificación analítica derivada
    'REGULAR'::varchar(30) AS transaction_nature,
    
    CASE 
        WHEN amount > 0 THEN 'INCOME'
        ELSE 'EXPENSE'
    END AS movement_type,

    true AS is_pnl,

    -- Auditoría
    source_row_id,
    loaded_at

FROM base
{{ config(materialized='view') }}

WITH cards_stg AS (
    SELECT * FROM {{ ref('stg_bankinter_card_personal') }}
    UNION ALL
    SELECT * FROM {{ ref('stg_bankinter_card_common') }}
    UNION ALL
    SELECT * FROM {{ ref('stg_bankinter_card_common_lledo') }}
),

base AS (
    SELECT
        t.source_hash,
        t.account_id,
        t.billing_date AS booking_date,
        t.value_date,
        t.description,
        t.amount,
        NULL::NUMERIC(18,2) as balance,
        t.source_row_id,
        t.loaded_at,
        a.account_name, 
        a.bank,
        a.account_type,
        a.owner AS account_ownership
    FROM cards_stg t
    LEFT JOIN {{ ref('dim_account') }} a
        ON t.account_id = a.account_id
),

classified_nature AS (
    SELECT
        *,
        CASE 
            WHEN amount > 0 THEN 'EXPENSE_REFUND'
            ELSE 'REGULAR'
        END AS transaction_nature
    FROM base
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
    CASE 
        WHEN account_ownership = 'común' THEN ROUND(amount / 2.0, 2)
        ELSE amount
    END AS personal_amount,
    balance,

    -- Clasificación analítica derivada
    transaction_nature,
    CASE 
        WHEN amount > 0 THEN 'INCOME'
        ELSE 'EXPENSE'
    END AS movement_type,

    TRUE AS is_pnl,

    -- Auditoría
    source_row_id,
    loaded_at
    
from classified_nature
{{ config(materialized='view') }}

WITH base AS (
    SELECT
        t.source_hash,
        t.account_id,
        t.booking_date,
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
    FROM {{ ref('stg_bankinter_account_personal') }} t
    LEFT JOIN {{ ref('dim_account') }} a
        ON t.account_id = a.account_id
),

classified_nature AS (
    SELECT
        *,
        CASE
            WHEN description ilike '%RECIBO PLATINUM%' 
                THEN 'CARD_SETTLEMENT'
            WHEN description ~* 'CUENTA T[UÚ] Y YO|RECARGA REVOLUT|TRASPASO INTERNO' 
                THEN 'INTERNAL_TRANSFER'
            WHEN description ~* 'TRANSF NOMI' 
                THEN 'SALARY'
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
    amount AS personal_amount,
    balance,

    -- Clasificación analítica derivada
    transaction_nature,

    CASE
        WHEN transaction_nature IN ('CARD_SETTLEMENT', 'INTERNAL_TRANSFER') THEN 'TRANSFER'
        WHEN amount > 0 THEN 'INCOME'
        WHEN amount < 0 THEN 'EXPENSE'
        ELSE 'NEUTRAL'
    END AS movement_type,

    CASE
        WHEN transaction_nature IN ('CARD_SETTLEMENT', 'INTERNAL_TRANSFER') THEN FALSE
        ELSE TRUE
    END AS is_pnl,

    -- Auditoría
    source_row_id,
    loaded_at

FROM classified_nature
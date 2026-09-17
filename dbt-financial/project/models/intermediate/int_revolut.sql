WITH base AS (
    SELECT
        t.source_hash,
        t.account_id,
        t.booking_date,
        t.value_date,
        t.description,
        t.amount,
        t.fee,
        t.balance,
        t.raw_transaction_type,
        t.source_row_id,
        t.loaded_at,
        da.account_name,
        da.bank,
        da.account_type,
        da.owner AS account_ownership
    FROM {{ ref('stg_revolut_account') }} t
    LEFT JOIN {{ source('stg', 'dim_account') }} da
        ON t.account_id = da.account_id
),

classified_nature AS (
    SELECT
        *,
        CASE
            WHEN raw_transaction_type IN ('Recargas', 'Cambio') 
              OR description ~* 'RECARGA|PAGO DE PABLO'
                THEN 'INTERNAL_TRANSFER'
            WHEN raw_transaction_type IN ('Recompensa', 'CASHBACK')
                THEN 'REWARD'
            WHEN raw_transaction_type = 'Reembolso de tarjeta'
                THEN 'EXPENSE_REFUND'
            ELSE 'REGULAR'
        END AS transaction_nature
    FROM base
)

SELECT
    -- Fechas
    value_date,
    booking_date,

    -- Transacción
    description,
    (amount + fee) AS amount,
    balance,
    (amount + fee) AS personal_amount,

    -- Clasificación analítica derivada
    transaction_nature,

    CASE
        WHEN transaction_nature = 'INTERNAL_TRANSFER' THEN 'TRANSFER'
        WHEN (amount + fee) > 0 THEN 'INCOME'
        WHEN (amount + fee) < 0 THEN 'EXPENSE'
        ELSE 'NEUTRAL'
    END AS movement_type,

    CASE
        WHEN transaction_nature = 'INTERNAL_TRANSFER' THEN FALSE
        ELSE TRUE
    END AS is_pnl,

    -- Identificadores y dimensiones de cuenta
    account_id,
    bank,
    account_type,
    account_ownership,
    source_hash,

    -- Auditoría
    source_row_id,
    loaded_at

from classified_nature
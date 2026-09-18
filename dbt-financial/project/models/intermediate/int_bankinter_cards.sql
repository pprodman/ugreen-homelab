WITH cards_staging AS (
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
        t.value_date,
        t.billing_date AS booking_date,
        t.description,
        t.amount,
        NULL::NUMERIC(18,2) AS balance,
        t.source_row_id,
        t.loaded_at,
        da.bank,
        da.account_type,
        da.owner AS account_ownership
    FROM cards_staging t
    LEFT JOIN {{ source('stg', 'dim_account') }} da
        ON t.account_id = da.account_id
),

classified_nature AS (
    SELECT
        *,
        CASE
            -- Reembolsos y devoluciones comerciales (importes positivos como 'ANUL.')
            WHEN amount > 0 THEN 'EXPENSE_REFUND'
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
    amount,
    balance,
    CASE
        WHEN account_ownership = 'common' THEN ROUND(amount / 2.0, 2)
        ELSE amount
    END AS personal_amount,

    -- Clasificación analítica derivada
    transaction_nature,

    CASE
        WHEN amount > 0 THEN 'INCOME'
        WHEN amount < 0 THEN 'EXPENSE'
        ELSE 'NEUTRAL'
    END AS movement_type,

    TRUE AS is_pnl,

    -- Identificadores y dimensiones de cuenta
    account_id,
    bank,
    account_type,
    account_ownership,
    source_hash,

    -- Auditoría
    source_row_id,
    loaded_at

FROM classified_nature
ORDER BY source_row_id ASC
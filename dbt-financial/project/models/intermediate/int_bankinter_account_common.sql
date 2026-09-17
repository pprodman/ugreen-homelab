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
        da.account_name,
        da.bank,
        da.account_type,
        da.owner AS account_ownership
    FROM {{ ref('stg_bankinter_account_common') }} t
    LEFT JOIN {{ source('stg', 'dim_account') }} da
        ON t.account_id = da.account_id
),

classified_nature AS (
    SELECT
        *,
        CASE
            WHEN description ilike '%RECIBO VISA CLASICA%' 
                THEN 'CARD_SETTLEMENT'
            WHEN description ~* 'TRANS/?PABLO|TRANSF I/? ?LLEDO' 
                THEN 'PARTNER_CONTRIBUTION'
            WHEN description ilike '%TRASPASO INTERNO%' 
                THEN 'INTERNAL_TRANSFER'
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
    ROUND(amount / 2.0, 2) AS personal_amount,

    -- Clasificación analítica derivada
    transaction_nature,

    CASE
        WHEN transaction_nature IN ('CARD_SETTLEMENT', 'INTERNAL_TRANSFER', 'PARTNER_CONTRIBUTION') THEN 'TRANSFER'
        WHEN amount > 0 THEN 'INCOME'
        WHEN amount < 0 THEN 'EXPENSE'
        ELSE 'NEUTRAL'
    END AS movement_type,

    CASE
        WHEN transaction_nature IN ('CARD_SETTLEMENT', 'INTERNAL_TRANSFER', 'PARTNER_CONTRIBUTION') THEN FALSE
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

FROM classified_nature
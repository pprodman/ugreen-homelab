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
            -- 1. Liquidación mensual de la tarjeta de la cuenta común
            WHEN description ILIKE '%RECIBO VISA CLASICA%' 
                THEN 'CARD_SETTLEMENT'
            -- 2. Aportaciones periódicas de ambos titulares (cubre con o sin barras/espacios)
            WHEN description ~* 'PABLO RODRIGUEZ|LLED[OÓ] AMOROS' 
                THEN 'PARTNER_CONTRIBUTION'
            -- 3. Traspasos internos
            WHEN description ILIKE '%TRASPASO INTERNO%' 
                THEN 'INTERNAL_TRANSFER'
            -- 4. Pagos por Bizum asociados a la cuenta común
            WHEN description ~* 'BIZUM' 
                THEN 'BIZUM'
            -- 5. Recibos de suministros, hipoteca, seguros y gastos ordinarios
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
ORDER BY source_row_id ASC
WITH base AS (
    SELECT
        t.source_hash,
        t.account_id,
        t.value_date,
        t.booking_date,
        t.description,
        t.amount,
        t.balance,
        t.source_row_id,
        t.loaded_at,
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
            -- 1. Traspasos internos (recargas con tarjeta/Apple Pay, cambios de divisa, migraciones de saldo o transferencias propias)
            WHEN description ~* 'RECARGA|CONVERSI[OÓ]N|BALANCE MIGRATION|PABLO RODRIGUEZ' 
                THEN 'INTERNAL_TRANSFER'
            -- 2. Recompensas, promociones y cashback
            WHEN description ~* 'REWARD|PROMO|PERK|CASHBACK' 
                THEN 'REWARD'
            -- 3. Devoluciones comerciales con tarjeta
            WHEN amount > 0 AND description NOT ILIKE '%TRANSFERENCIA DE%' 
                THEN 'EXPENSE_REFUND'
            -- 4. Compras habituales y transferencias entre particulares
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
    amount AS personal_amount,

    -- Clasificación analítica derivada
    transaction_nature,

    CASE
        WHEN transaction_nature = 'INTERNAL_TRANSFER' THEN 'TRANSFER'
        WHEN amount > 0 THEN 'INCOME'
        WHEN amount < 0 THEN 'EXPENSE'
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

FROM classified_nature
ORDER BY source_row_id ASC
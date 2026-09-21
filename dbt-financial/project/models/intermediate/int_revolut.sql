WITH base AS (
    SELECT
        t.source_hash,
        t.account_id,
        t.value_date,
        t.booking_date,
        t.description,
        t.amount,
        t.balance,
        t.raw_transaction_type,
        t.source_row_id,
        t.loaded_at,
        da.bank,
        da.account_type,
        da.owner AS account_ownership
    FROM {{ ref('stg_revolut_account') }} t
    LEFT JOIN {{ source('stg', 'dim_account') }} da
        ON t.account_id = da.account_id
    WHERE t.state = 'COMPLETADO' -- Excluye las operaciones fallidas o devueltas
),

classified_nature AS (
    SELECT
        *,
        CASE
            -- 1. Fondeos nativos de Revolut
            WHEN raw_transaction_type IN ('Recargas') 
                THEN 'INTERNAL_TRANSFER'
            -- 2. Transferencias: aislar migraciones de saldo y fondeos propios
            WHEN raw_transaction_type = 'Transferir' 
                 AND description ~* 'balance migration|pablo rodriguez' 
                THEN 'INTERNAL_TRANSFER'
            -- 3. Bonificaciones y cashback
            WHEN raw_transaction_type IN ('Recompensa', 'CASHBACK') 
                THEN 'REWARD'
            -- 4. Devoluciones comerciales explícitas
            WHEN raw_transaction_type = 'Reembolso de tarjeta' 
                THEN 'EXPENSE_REFUND'
            -- 5. Pagos con tarjeta y transferencias con terceros
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
        WHEN transaction_nature = 'EXPENSE_REFUND' THEN 'EXPENSE'
        WHEN amount > 0 THEN 'INCOME'
        WHEN amount < 0 THEN 'EXPENSE'
        ELSE 'NEUTRAL'
    END AS movement_type,

    (transaction_nature != 'INTERNAL_TRANSFER') AS is_pnl,

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
WITH unioned AS (
    SELECT * FROM {{ ref('int_bankinter_account_personal') }}
    UNION ALL
    SELECT * FROM {{ ref('int_bankinter_account_common') }}
    UNION ALL
    SELECT * FROM {{ ref('int_bankinter_cards') }}
    UNION ALL
    SELECT * FROM {{ ref('int_cash') }}
    UNION ALL
    SELECT * FROM {{ ref('int_revolut') }}
)

SELECT
    -- 1. Fechas
    value_date,
    booking_date,

    -- 2. Detalle de la transacción e importes
    description,
    amount,
    personal_amount,
    balance,

    -- 3. Clasificación contable básica
    transaction_nature,
    movement_type,
    is_pnl,

    -- 4. Dimensiones de la cuenta / entidad
    account_id,
    bank,
    account_type,
    account_ownership,

    -- 5. Auditoría e identificadores técnicos (al final)
    source_row_id,
    source_hash,
    loaded_at

FROM unioned
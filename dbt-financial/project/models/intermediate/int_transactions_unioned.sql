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
    -- Clave primaria única generada a partir del hash de origen
    source_hash AS transaction_id,

    -- Fechas
    value_date,
    booking_date,

    -- Detalle transacción
    description,
    amount,
    balance,
    personal_amount,

    -- Clasificación contable
    transaction_nature,
    movement_type,
    is_pnl,

    -- Dimensiones de cuenta
    account_id,
    bank,
    account_type,
    account_ownership,

    -- Auditoría
    source_hash,
    source_row_id,
    loaded_at

FROM unioned
SELECT
    fecha_contable AS transaction_date,
    fecha_valor AS value_date,
    TRIM(descripcion) AS description,
    importe AS amount,
    saldo AS balance,

    source_row_id,
    source_hash,
    loaded_at,
    updated_at

FROM {{ source('raw', 'bankinter_account_personal') }}
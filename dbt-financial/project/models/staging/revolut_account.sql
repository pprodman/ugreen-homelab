SELECT
    tipo AS transaction_type,
    producto AS product,
    fecha_inicio AS start_date,
    fecha_fin AS end_date,
    TRIM(descripcion) AS description,
    importe AS amount,
    comision AS fee,
    divisa AS currency,
    state AS status,
    saldo AS balance,

    source_row_id,
    source_hash,
    loaded_at,
    updated_at

FROM {{ source('raw', 'revolut_account') }}
WITH transactions AS (

    -- Bankinter account personal
    SELECT
        'BANKINTER_ACCOUNT_PERSONAL' AS source_name,
        'BANKINTER_ACCOUNT_PERSONAL' AS account_code,

        transaction_date,
        value_date,
        description,
        amount,
        CAST(NULL AS TEXT) AS currency,
        balance,

        source_row_id,
        source_hash,
        loaded_at,
        updated_at

    FROM {{ ref('bankinter_account_personal') }}


    UNION ALL


    -- Bankinter account common
    SELECT
        'BANKINTER_ACCOUNT_COMMON' AS source_name,
        'BANKINTER_ACCOUNT_COMMON' AS account_code,

        transaction_date, 
        description,
        amount,
        CAST(NULL AS TEXT) AS currency,
        balance,

        source_row_id,
        source_hash,
        loaded_at,
        updated_at

    FROM {{ ref('bankinter_account_common') }}


    UNION ALL


    -- Bankinter card personal
    SELECT
        'BANKINTER_CARD_PERSONAL' AS source_name,
        'BANKINTER_CARD_PERSONAL' AS account_code,

        transaction_date,
        NULL AS value_date,
        description,
        amount,
        CAST(NULL AS TEXT) AS currency,
        NULL AS balance,

        source_row_id,
        source_hash,
        loaded_at,
        updated_at

    FROM {{ ref('bankinter_card_personal') }}


    UNION ALL


    -- Bankinter card common
    SELECT
        'BANKINTER_CARD_COMMON' AS source_name,
        'BANKINTER_CARD_COMMON' AS account_code,

        transaction_date,
        NULL AS value_date,
        description,
        amount,
        CAST(NULL AS TEXT) AS currency,
        NULL AS balance,

        source_row_id,
        source_hash,
        loaded_at,
        updated_at

    FROM {{ ref('bankinter_card_common') }}


    UNION ALL


    -- Bankinter card common Lledo
    SELECT
        'BANKINTER_CARD_COMMON_LLEDO' AS source_name,
        'BANKINTER_CARD_COMMON_LLEDO' AS account_code,

        transaction_date,
        NULL AS value_date,
        description,
        amount,
        CAST(NULL AS TEXT) AS currency,
        NULL AS balance,

        source_row_id,
        source_hash,
        loaded_at,
        updated_at

    FROM {{ ref('bankinter_card_common_lledo') }}


    UNION ALL


    -- Revolut
    SELECT
        'REVOLUT_ACCOUNT' AS source_name,
        'REVOLUT_ACCOUNT' AS account_code,

        start_date AS transaction_date,
        end_date AS value_date,
        description,
        amount,
        currency,
        balance,

        source_row_id,
        source_hash,
        loaded_at,
        updated_at

    FROM {{ ref('revolut_account') }}


    UNION ALL


    -- Cash
    SELECT
        'CASH' AS source_name,
        'CASH' AS account_code,

        transaction_date,
        NULL AS value_date,
        description,
        amount,
        CAST(NULL AS TEXT) AS currency,
        NULL AS balance,

        source_row_id,
        source_hash, 
        loaded_at,
        updated_at

    FROM {{ ref('cash') }}

)

SELECT
    MD5(
        source_name
        || '|'
        || source_row_id::TEXT
    ) AS transaction_id,

    account_code AS account_id,

    transaction_date,
    value_date,
    description,
    amount,

    COALESCE(currency, 'EUR') AS currency,

    balance,

    source_name,
    source_row_id,
    source_hash,

    loaded_at,
    updated_at

FROM transactions
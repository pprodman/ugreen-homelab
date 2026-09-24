{{ config(
    materialized = 'view',
    tags = ['intermediate', 'financial_core']
) }}

WITH base_unioned AS (
    SELECT * FROM {{ ref('int_transactions_unioned') }}
),

-- 1. Normalización de Personas (Insensible a ';', '#$', '/' y espacios)
persons_matched AS (
    SELECT DISTINCT ON (b.source_hash)
        b.*,
        mp.person_name,
        CASE 
            WHEN mp.person_name IS NOT NULL AND b.transaction_nature = 'BIZUM' AND b.amount > 0
                THEN 'Bizum de: ' || mp.person_name
            WHEN mp.person_name IS NOT NULL AND b.transaction_nature = 'BIZUM' AND b.amount < 0
                THEN 'Bizum a: ' || mp.person_name
            WHEN mp.person_name IS NOT NULL AND b.description ~* '(TRANS|TRANSFERENCIA)' AND b.amount > 0
                THEN 'Transf de: ' || mp.person_name
            WHEN mp.person_name IS NOT NULL AND b.description ~* '(TRANS|TRANSFERENCIA)' AND b.amount < 0
                THEN 'Transf a: ' || mp.person_name
            ELSE b.description 
        END AS clean_description
    FROM base_unioned b
    LEFT JOIN {{ source('stg', 'master_participants') }} mp
        ON REGEXP_REPLACE(b.description, '[^a-zA-Z0-9]+', ' ', 'g') 
           ILIKE '%' || REGEXP_REPLACE(mp.keyword, '[^a-zA-Z0-9]+', ' ', 'g') || '%'
    ORDER BY 
        b.source_hash, 
        LENGTH(mp.keyword) DESC NULLS LAST
),

-- 2. Motor de Reglas (rules_mapping con normalización de caracteres)
rules_matched AS (
    SELECT DISTINCT ON (b.source_hash)
        b.*,
        r.category_id   AS matched_category_id,
        r.merchant_name AS matched_merchant_name
    FROM persons_matched b
    LEFT JOIN {{ source('stg', 'rules_mapping') }} r
        ON REGEXP_REPLACE(b.description, '[^a-zA-Z0-9]+', ' ', 'g') 
           ILIKE '%' || REGEXP_REPLACE(r.keyword, '[^a-zA-Z0-9]+', ' ', 'g') || '%'
        OR REGEXP_REPLACE(b.clean_description, '[^a-zA-Z0-9]+', ' ', 'g') 
           ILIKE '%' || REGEXP_REPLACE(r.keyword, '[^a-zA-Z0-9]+', ' ', 'g') || '%'
    ORDER BY 
        b.source_hash, 
        r.priority DESC NULLS LAST, 
        LENGTH(r.keyword) DESC NULLS LAST
),

-- 3. Overrides manuales, resolución de comercio y lógica bidireccional de categorías
adjustments_applied AS (
    SELECT
        r.*,
        adj.category_id_override,
        adj.merchant_override,
        adj.adjustment_type,
        adj.adjustment_amount,
        adj.reason AS adjustment_reason,

        -- A. RESOLUCIÓN DE CATEGORÍA SEGÚN SIGNO Y CANAL
        COALESCE(
            adj.category_id_override,
            r.matched_category_id,
            CASE
                -- Caso Pareja (Lledó)
                WHEN r.person_name = 'Lledó Amorós' AND r.amount < 0 AND r.account_ownership = 'personal'
                    THEN 'PAREJA_COMPENSA'
                WHEN r.person_name = 'Lledó Amorós' AND r.amount > 0 AND r.account_ownership = 'common'
                    THEN 'MOV_FONDEO_COMUN'
                WHEN r.person_name = 'Lledó Amorós' AND r.amount > 0
                    THEN 'ING_BIZUM'

                -- Personas / Bizum según signo
                WHEN (r.person_name IS NOT NULL OR r.transaction_nature = 'BIZUM') AND r.amount > 0
                    THEN CASE WHEN r.transaction_nature = 'BIZUM' THEN 'ING_BIZUM' ELSE 'ING_TRANSFERENCIAS' END
                WHEN (r.person_name IS NOT NULL OR r.transaction_nature = 'BIZUM') AND r.amount < 0
                    THEN CASE WHEN r.transaction_nature = 'BIZUM' THEN 'VAR_BIZUM' ELSE 'VAR_OTROS' END

                -- Naturalezas bancarias automáticas
                WHEN r.transaction_nature = 'SALARY'              THEN 'ING_NOMINA'
                WHEN r.transaction_nature = 'MORTGAGE_PAYMENT'     THEN 'FIX_HIPOTECA'
                WHEN r.transaction_nature = 'CARD_SETTLEMENT'      THEN 'MOV_LIQ_TARJETA'
                WHEN r.transaction_nature = 'INTERNAL_TRANSFER'    THEN 'MOV_TRASPASO'
                WHEN r.transaction_nature = 'PARTNER_CONTRIBUTION' THEN 'MOV_FONDEO_COMUN'
                WHEN r.transaction_nature = 'LOAN_DISBURSEMENT'    THEN 'CPX_DISPOSICION'
                WHEN r.transaction_nature = 'EXPENSE_REFUND'       THEN 'VAR_DEVOLUCION'
                WHEN r.transaction_nature = 'REWARD'               THEN 'ING_RENDIMIENTOS'

                -- Fallback por signo
                WHEN r.amount > 0 THEN 'ING_TRANSFERENCIAS'
                ELSE 'VAR_OTROS'
            END
        ) AS final_category_id,

        -- B. RESOLUCIÓN DE COMERCIO / BENEFICIARIO
        -- Resolución del comercio o persona
        COALESCE(
            -- 1. Override manual en master_adjustments
            NULLIF(TRIM(adj.merchant_override), ''),

            -- 2. Comercio de rules_mapping (si está vacío, pasa al siguiente)
            NULLIF(TRIM(r.matched_merchant_name), ''),

            -- 3. Persona identificada en participants (Bizums y Transferencias)
            NULLIF(TRIM(r.person_name), ''),

            -- 4. Datáfonos de tarjetas (texto antes de la coma)
            CASE 
                WHEN r.account_type = 'card' AND r.description LIKE '%,%' 
                THEN TRIM(SPLIT_PART(r.description, ',', 1)) 
            END,

            -- 5. Extracción sintáctica de recibos bancarios
            CASE 
                WHEN r.description ~* '^(RECIBO|RECIB)\s*\/?' 
                THEN TRIM(REGEXP_REPLACE(r.description, '^(RECIBO|RECIB)\s*\/?\s*', '', 'i')) 
            END,

            -- 6. Extracción sintáctica de transferencias (si no está en participants)
            CASE 
                WHEN r.description ~* '^(TRANSF\s+OTR\s*\/?|TRANSF\s+I\s*\/?|TRANS\s*\/?|TRANSFERENCIA\s+DE\s+|TRANSFERENCIA\s+A\s+)' 
                THEN TRIM(REGEXP_REPLACE(r.description, '^(TRANSF\s+OTR\s*\/?|TRANSF\s+I\s*\/?|TRANS\s*\/?|TRANSFERENCIA\s+DE\s+|TRANSFERENCIA\s+A\s+)\s*', '', 'i')) 
            END,

            -- 7. Extracción sintáctica de Bizums a particulares no fichados
            CASE 
                WHEN r.description ~* '^(DEV\s+)?PAGO\s+BIZUM\s+(A|DE)\s+' 
                THEN TRIM(REGEXP_REPLACE(REGEXP_REPLACE(r.description, '^(DEV\s+)?PAGO\s+BIZUM\s+(A|DE)\s+', '', 'i'), '[^a-zA-Z0-9]+', ' ', 'g')) 
            END,

            '-'
        ) AS final_merchant_name

    FROM rules_matched r
    LEFT JOIN {{ source('stg', 'master_adjustments') }} adj
        ON r.source_hash = adj.source_hash
),

-- 4. Cruce dimensional con dim_categories
dimensional_enrichment AS (
    SELECT
        a.*,
        cat.group_name,
        cat.category_name,
        cat.subcategory_name,
        COALESCE(cat.is_pnl, a.is_pnl) AS resolved_is_pnl,
        COALESCE(cat.movement_type, a.movement_type) AS resolved_movement_type
    FROM adjustments_applied a
    LEFT JOIN {{ source('stg', 'dim_categories') }} cat
        ON a.final_category_id = cat.category_id
),

-- 5. Cálculos finales y ordenación de columnas
final_calculations AS (
    SELECT
        -- Fechas
        value_date,
        booking_date,

        -- Importes
        amount,

        CASE
            WHEN adjustment_type = 'PARTNER_EXPENSE' THEN 0.00
            WHEN adjustment_type = 'MY_EXPENSE'      THEN amount
            WHEN adjustment_type = 'PARTIAL_EXPENSE' 
                THEN -ROUND((ABS(amount) - ABS(COALESCE(adjustment_amount, 0))) * 0.5, 2)
            WHEN account_ownership = 'personal' THEN amount
            WHEN account_ownership = 'common' AND resolved_movement_type IN ('EXPENSE', 'INCOME')
                THEN ROUND(amount * 0.5, 2)
            ELSE 0.00
        END AS personal_amount,

        balance,

        -- Flags contables
        resolved_is_pnl AS is_pnl,

        CASE
            WHEN NOT resolved_is_pnl THEN FALSE
            WHEN resolved_movement_type = 'TRANSFER' THEN FALSE
            WHEN adjustment_type IN ('PARTNER_EXPENSE', 'MY_EXPENSE') THEN FALSE
            WHEN adjustment_type = 'PARTIAL_EXPENSE' THEN TRUE
            WHEN account_ownership = 'common' THEN TRUE
            ELSE FALSE
        END AS is_shared,

        resolved_movement_type AS movement_type,
        transaction_nature,

        -- Taxonomía dimensional
        final_category_id AS category_id,
        group_name,
        category_name,
        subcategory_name,

        -- Entidad y descripciones
        final_merchant_name AS merchant_name,
        clean_description,
        description AS raw_description,

        -- Contexto de cuenta
        account_id,
        bank,
        account_type,
        account_ownership,

        -- Ajustes manuales
        adjustment_type,
        adjustment_amount,
        adjustment_reason,

        -- Auditoría e identificadores técnicos al final
        loaded_at,
        source_row_id,
        source_hash

    FROM dimensional_enrichment
)

SELECT * FROM final_calculations
WITH base_unioned AS (
    SELECT * FROM {{ ref('int_transactions_unioned') }}
),

-- 1. Cruce con master_participants (inmune a signos ';', '#$', tildes y DOBLES ESPACIOS)
persons_matched AS (
    SELECT DISTINCT ON (b.source_hash)
        b.*,
        NULLIF(TRIM(mp.person_name), '') AS person_name
    FROM base_unioned b
    LEFT JOIN {{ source('stg', 'master_participants') }} mp
        ON REGEXP_REPLACE(REGEXP_REPLACE(TRANSLATE(b.description, 'ÁÉÍÓÚáéíóúÜüÑñ', 'AEIOUaeiouUuNn'), '[^a-zA-Z0-9]+', ' ', 'g'), '\s+', ' ', 'g')
           ILIKE '%' || REGEXP_REPLACE(REGEXP_REPLACE(TRANSLATE(mp.keyword, 'ÁÉÍÓÚáéíóúÜüÑñ', 'AEIOUaeiouUuNn'), '[^a-zA-Z0-9]+', ' ', 'g'), '\s+', ' ', 'g') || '%'
    ORDER BY 
        b.source_hash, 
        LENGTH(mp.keyword) DESC NULLS LAST
),

-- 2. Motor de Reglas comerciales (rules_mapping)
rules_matched AS (
    SELECT DISTINCT ON (b.source_hash)
        b.*,
        r.category_id AS matched_category_id,
        -- Si en rules_mapping hay '-', 'N/A' o vacío, se fuerza a NULL para que no bloquee a participants
        CASE 
            WHEN TRIM(r.merchant_name) IN ('', '-', '–', '—', 'N/A', 'null', 'None') THEN NULL 
            ELSE TRIM(r.merchant_name) 
        END AS matched_merchant_name
    FROM persons_matched b
    LEFT JOIN {{ source('stg', 'rules_mapping') }} r
        ON REGEXP_REPLACE(REGEXP_REPLACE(TRANSLATE(b.description, 'ÁÉÍÓÚáéíóúÜüÑñ', 'AEIOUaeiouUuNn'), '[^a-zA-Z0-9]+', ' ', 'g'), '\s+', ' ', 'g')
           ILIKE '%' || REGEXP_REPLACE(REGEXP_REPLACE(TRANSLATE(r.keyword, 'ÁÉÍÓÚáéíóúÜüÑñ', 'AEIOUaeiouUuNn'), '[^a-zA-Z0-9]+', ' ', 'g'), '\s+', ' ', 'g') || '%'
    ORDER BY 
        b.source_hash, 
        r.priority DESC NULLS LAST, 
        LENGTH(r.keyword) DESC NULLS LAST
),

-- 3. Overrides manuales y resolución en capas de categoría y comercio
adjustments_applied AS (
    SELECT
        r.*,
        adj.category_id_override,
        adj.merchant_override,
        adj.adjustment_type,
        adj.adjustment_amount,
        adj.reason AS adjustment_reason,

        -- A. RESOLUCIÓN DE CATEGORÍA
        COALESCE(
            adj.category_id_override,
            r.matched_category_id,
            CASE
                -- Caso Pareja (Lledó)
                WHEN r.person_name ILIKE '%Lledo%' AND r.amount < 0 AND r.account_ownership = 'personal'
                    THEN 'VAR_OTROS'
                WHEN r.person_name ILIKE '%Lledo%' AND r.amount < 0 AND r.account_ownership = 'common'
                    THEN 'MOV_TRASPASO'
                WHEN r.person_name ILIKE '%Lledo%' AND r.amount > 0 AND r.account_ownership = 'common'
                    THEN 'ING_TRANSFERENCIAS'
                WHEN r.person_name ILIKE '%Lledo%' AND r.amount > 0
                    THEN 'ING_BIZUM'

                -- Personas / Bizum / Transferencias según signo
                WHEN (r.person_name IS NOT NULL OR r.transaction_nature = 'BIZUM') AND r.amount > 0
                    THEN CASE WHEN r.transaction_nature = 'BIZUM' THEN 'ING_BIZUM' ELSE 'ING_TRANSFERENCIAS' END
                WHEN (r.person_name IS NOT NULL OR r.transaction_nature = 'BIZUM') AND r.amount < 0
                    THEN CASE WHEN r.transaction_nature = 'BIZUM' THEN 'VAR_BIZUM' ELSE 'VAR_OTROS' END

                -- Naturalezas bancarias automáticas
                WHEN r.transaction_nature = 'SALARY'              THEN 'ING_NOMINA'
                WHEN r.transaction_nature = 'MORTGAGE_PAYMENT'     THEN 'FIX_HIPOTECA'
                WHEN r.transaction_nature = 'CARD_SETTLEMENT'      THEN 'MOV_LIQ_TARJETA'
                WHEN r.transaction_nature = 'INTERNAL_TRANSFER'    THEN 'MOV_TRASPASO'
                WHEN r.transaction_nature = 'PARTNER_CONTRIBUTION' THEN 'ING_TRANSFERENCIAS'
                WHEN r.transaction_nature = 'LOAN_DISBURSEMENT'    THEN 'CPX_DISPOSICION'
                WHEN r.transaction_nature = 'EXPENSE_REFUND'       THEN 'VAR_COM_ONLINE'
                WHEN r.transaction_nature = 'REWARD'               THEN 'ING_RENDIMIENTOS'

                -- Fallback general por signo
                WHEN r.amount > 0 THEN 'ING_TRANSFERENCIAS'
                ELSE 'VAR_OTROS'
            END
        ) AS final_category_id,

        -- B. RESOLUCIÓN DE MERCHANT_NAME EN 5 CAPAS
        COALESCE(
            -- 1. Override manual en master_adjustments
            NULLIF(TRIM(adj.merchant_override), ''),

            -- 2. Comercio oficial de rules_mapping (ej: Mercadona, Endesa)
            r.matched_merchant_name,

            -- 3. Persona identificada en master_participants (¡Aquí entrarán todos tus Bizums!)
            r.person_name,

            -- 4. Auto-curación de Bizum si la persona no estaba registrada
            CASE 
                WHEN r.description ~* 'BIZUM' 
                THEN NULLIF(INITCAP(TRIM(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(r.description, '.*?\mBIZUM\s+(A|DE|PARA)\s+', '', 'i'),
                            '[;#$_/\\-]+', ' ', 'g'
                        ),
                        '\s+', ' ', 'g'
                    )
                )), '')
            END,

            -- 5. Auto-curación de Transferencias si no estaba en participants
            CASE 
                WHEN r.description ~* '\m(TRA\s*NS|TRANSF|TRANSFERENCIA)\M' 
                THEN NULLIF(INITCAP(TRIM(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(
                                r.description, 
                                '.*?\m(TRA\s*NS\s*F?|TRANSF?|TRANSFERENCIA)\s*(INTERNA|INM|OTR[AS]*\s+ENTID|OTR[AS]*|I|NOMI[A-Z]*|\/)?\s*(\/|\:)?\s*', 
                                '', 
                                'i'
                            ),
                            '[;#$_/\\-]+', ' ', 'g'
                        ),
                        '\s+', ' ', 'g'
                    )
                )), '')
            END,

            -- 6. Datáfonos de tarjetas (texto antes de la primera coma)
            CASE 
                WHEN r.account_type = 'card' AND r.description LIKE '%,%' 
                THEN NULLIF(TRIM(SPLIT_PART(r.description, ',', 1)), '') 
            END,

            -- 7. Recibos bancarios
            CASE 
                WHEN r.description ~* '^(RECIBO|RECIB)\s*\/?' 
                THEN NULLIF(TRIM(REGEXP_REPLACE(r.description, '^(RECIBO|RECIB)\s*\/?\s*', '', 'i')), '') 
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

-- 5. Cálculos finales y estructura de salida
final_calculations AS (
    SELECT
        value_date,
        booking_date,
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
        resolved_is_pnl AS is_pnl,

        CASE
            WHEN adjustment_type IN ('PARTNER_EXPENSE', 'MY_EXPENSE') THEN FALSE
            WHEN adjustment_type = 'PARTIAL_EXPENSE' THEN TRUE
            WHEN resolved_movement_type = 'TRANSFER' THEN FALSE
            WHEN account_ownership = 'common' THEN TRUE
            WHEN NOT resolved_is_pnl THEN FALSE
            ELSE FALSE
        END AS is_shared,

        resolved_movement_type AS movement_type,

        transaction_nature,

        final_category_id AS category_id,
        group_name,
        category_name,
        subcategory_name,

        final_merchant_name AS merchant_name,
        description AS raw_description,

        account_id,
        bank,
        account_type,
        account_ownership,

        adjustment_type,
        adjustment_amount,
        adjustment_reason,

        loaded_at,
        source_row_id,
        source_hash

    FROM dimensional_enrichment
)

SELECT * FROM final_calculations
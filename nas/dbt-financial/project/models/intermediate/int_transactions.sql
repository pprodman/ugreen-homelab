WITH base AS (
    SELECT * FROM {{ ref('int_transactions_unioned') }}
),

/* ================================================================
   1. PARTICIPANTES
   Detección inmune a \xa0 (CHR(160)), signos '#$', ';' y tildes.
   ================================================================ */
with_participant AS (
    SELECT DISTINCT ON (b.source_hash)
        b.*,
        p.person_name AS participant_name
    FROM base b
    LEFT JOIN {{ source('stg', 'master_participants') }} p
        ON TRANSLATE(
            REGEXP_REPLACE(
                REPLACE(b.description, CHR(160), ' '), 
                '[^a-zA-Z0-9]+', ' ', 'g'
            ), 
            'ÁÉÍÓÚáéíóú', 'AEIOUaeiou'
           )
           ILIKE '%' || 
           TRANSLATE(
            REGEXP_REPLACE(p.keyword, '[^a-zA-Z0-9]+', ' ', 'g'), 
            'ÁÉÍÓÚáéíóú', 'AEIOUaeiou'
           ) || '%'
    ORDER BY 
        b.source_hash, 
        LENGTH(p.keyword) DESC NULLS LAST
),

/* ================================================================
   2. REGLAS COMERCIALES (rules_mapping)
   ================================================================ */
with_mapping AS (
    SELECT
        p.*,
        r.category_id AS rule_category_id,
        NULLIF(TRIM(r.merchant_name), '') AS rule_merchant,
        r.priority
    FROM with_participant p
    LEFT JOIN {{ source('stg', 'rules_mapping') }} r
        ON TRANSLATE(
            REGEXP_REPLACE(
                REPLACE(p.description, CHR(160), ' '), 
                '[^a-zA-Z0-9]+', ' ', 'g'
            ), 
            'ÁÉÍÓÚáéíóú', 'AEIOUaeiou'
           )
           ILIKE '%' || 
           TRANSLATE(
            REGEXP_REPLACE(r.keyword, '[^a-zA-Z0-9]+', ' ', 'g'), 
            'ÁÉÍÓÚáéíóú', 'AEIOUaeiou'
           ) || '%'
),

mapping_ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY source_hash
            ORDER BY priority DESC NULLS LAST, LENGTH(description) DESC
        ) AS mapping_rank
    FROM with_mapping
),

/* ================================================================
   3. REGLAS Y AJUSTES MANUALES (master_adjustments)
   ================================================================ */
with_adjustments AS (
    SELECT
        m.*,
        a.category_id_override,
        a.merchant_override,
        a.adjustment_type,
        a.adjustment_amount,
        a.reason AS adjustment_reason
    FROM mapping_ranked m
    LEFT JOIN {{ source('stg', 'master_adjustments') }} a
        ON m.source_hash = a.source_hash
    WHERE m.mapping_rank = 1
),

/* ================================================================
   4. RESOLUCIÓN FINAL DE CATEGORÍA Y COMERCIO
   ================================================================ */
resolved AS (
    SELECT
        a.*,

        -- A. RESOLUCIÓN DE CATEGORÍA
        COALESCE(
            -- 1. Override manual
            a.category_id_override,

            -- 2. CASUÍSTICA ESPECÍFICA LLEDÓ AMORÓS
            CASE 
                -- Compensaciones mutuas directas entre cuentas personales (en ambas direcciones)
                WHEN a.participant_name = 'Lledó Amorós' AND a.account_ownership = 'personal'
                    THEN 'PAREJA_COMPENSA'
                -- En cuenta común: entradas son fondeo, salidas son traspaso
                WHEN a.participant_name = 'Lledó Amorós' AND a.account_ownership = 'common' AND a.amount > 0
                    THEN 'MOV_FONDEO_COMUN'
                WHEN a.participant_name = 'Lledó Amorós' AND a.account_ownership = 'common' AND a.amount < 0
                    THEN 'MOV_TRASPASO'
            END,

            -- 3. CASUÍSTICA ESPECÍFICA PABLO RODRÍGUEZ
            CASE
                WHEN a.participant_name = 'Pablo Rodríguez' AND a.account_ownership = 'common' AND a.amount > 0
                    THEN 'MOV_FONDEO_COMUN'
                WHEN a.participant_name = 'Pablo Rodríguez'
                    THEN 'MOV_TRASPASO'
            END,

            -- 4. Regla comercial de rules_mapping
            a.rule_category_id,

            -- 5. Fallback por naturaleza bancaria intrínseca
            CASE
                WHEN a.transaction_nature = 'PARTNER_CONTRIBUTION' AND a.amount > 0 THEN 'MOV_FONDEO_COMUN'
                WHEN a.transaction_nature = 'PARTNER_CONTRIBUTION' AND a.amount < 0 THEN 'MOV_TRASPASO'
                WHEN a.transaction_nature = 'INTERNAL_TRANSFER'    THEN 'MOV_TRASPASO'
                WHEN a.transaction_nature = 'CARD_SETTLEMENT'      THEN 'MOV_LIQ_TARJETA'
                WHEN a.transaction_nature = 'MORTGAGE_PAYMENT'     THEN 'FIX_HIPOTECA'
                WHEN a.transaction_nature = 'LOAN_DISBURSEMENT'    THEN 'CPX_DISPOSICION'
                WHEN a.transaction_nature = 'SALARY'              THEN 'ING_NOMINA'
                WHEN a.transaction_nature = 'EXPENSE_REFUND'       THEN 'VAR_DEVOLUCION'
                WHEN a.transaction_nature = 'REWARD'               THEN 'ING_RENDIMIENTOS'
                WHEN a.transaction_nature = 'BIZUM' AND a.amount > 0 THEN 'ING_BIZUM'
                WHEN a.transaction_nature = 'BIZUM' AND a.amount < 0 THEN 'VAR_BIZUM'
                WHEN a.amount > 0                                  THEN 'ING_TRANSFERENCIAS'
                ELSE 'VAR_OTROS'
            END
        ) AS final_category_id,

        -- B. RESOLUCIÓN DE COMERCIO (Neutral '-' para ambos en movimientos internos)
        COALESCE(
            -- 1. Override manual
            NULLIF(TRIM(a.merchant_override), ''),

            -- 2. Regla comercial explícita
            NULLIF(TRIM(a.rule_merchant), ''),

            -- 3. Compensaciones de pareja y traspasos/fondeos internos homogéneos
            CASE
                WHEN a.participant_name IN ('Lledó Amorós', 'Pablo Rodríguez')
                    THEN '-'
            END,

            -- 4. Persona física identificada (amigos, familiares, terceros)
            NULLIF(TRIM(a.participant_name), ''),

            -- 5. Extracción automática en Bizums no fichados
            CASE 
                WHEN a.description ~* 'BIZUM' 
                THEN INITCAP(TRIM(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(REPLACE(a.description, CHR(160), ' '), '^(DEV\s+)?(PAGO\s+)?BIZUM\s+(A|DE|PARA)\s+', '', 'i'),
                            '[;#$_/\\-]+', ' ', 'g'
                        ),
                        '\s+', ' ', 'g'
                    )
                ))
            END,

            -- 6. Extracción automática en Transferencias de particulares
            CASE 
                WHEN a.description ~* '^(TRA\s*NS|TRANSF|TRANSFERENCIA)' 
                THEN INITCAP(TRIM(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(
                                REPLACE(a.description, CHR(160), ' '), 
                                '^(TRA\s*NS\s*F?|TRANSF?)\s*(INTERNA|OTR[AS]*\s+ENTID|OTR[AS]*|I|NOMI[A-Z]*|\/)?\s*(\/|\:)?\s*|^(TRANSFERENCIA\s+(DE|A|FAVOR DE))\s*', 
                                '', 
                                'i'
                            ),
                            '[;#$_/\\-]+', ' ', 'g'
                        ),
                        '\s+', ' ', 'g'
                    )
                ))
            END,

            -- 7. Datáfonos de tarjetas
            CASE 
                WHEN a.account_type = 'card' AND a.description LIKE '%,%' 
                    THEN TRIM(SPLIT_PART(a.description, ',', 1))
                WHEN a.account_type = 'card' AND LENGTH(TRIM(a.description)) > 0
                    THEN INITCAP(TRIM(a.description))
            END,

            -- 8. Recibos bancarios
            CASE 
                WHEN a.description ~* '^(RECIBO|RECIB)\s*\/?' 
                THEN TRIM(REGEXP_REPLACE(a.description, '^(RECIBO|RECIB)\s*\/?\s*', '', 'i')) 
            END,

            'No Identificado'
        ) AS final_merchant

    FROM with_adjustments a
),

/* ================================================================
   5. CRUCE DIMENSIONAL CON CATEGORÍAS
   ================================================================ */
with_category AS (
    SELECT
        r.*,
        c.group_name,
        c.category_name,
        c.subcategory_name,
        COALESCE(c.is_pnl, FALSE) AS category_is_pnl,
        CASE
            WHEN r.final_category_id = 'PAREJA_COMPENSA' AND r.amount > 0 THEN 'INCOME'
            WHEN r.final_category_id = 'PAREJA_COMPENSA' AND r.amount < 0 THEN 'EXPENSE'
            ELSE COALESCE(c.movement_type, r.movement_type)
        END AS resolved_movement_type
    FROM resolved r
    LEFT JOIN {{ source('stg', 'dim_categories') }} c
        ON r.final_category_id = c.category_id
),

/* ================================================================
   6. CÁLCULOS FINANCIEROS Y AUDITORÍA
   ================================================================ */
final AS (
    SELECT
        -- Identificadores y cuentas
        source_hash,
        account_id,
        bank,
        account_type,
        account_ownership,

        -- Fechas (base económica en value_date)
        value_date,
        booking_date,
        DATE_TRUNC('month', value_date)::DATE AS year_month,
        EXTRACT(YEAR FROM value_date)::INTEGER AS year,
        EXTRACT(MONTH FROM value_date)::INTEGER AS month,

        -- Textos y clasificación
        description,
        amount,
        balance,

        transaction_nature,
        resolved_movement_type AS movement_type,
        final_category_id AS category_id,
        group_name,
        category_name,
        subcategory_name,

        -- Beneficiario / Contacto
        final_merchant AS merchant,
        participant_name,

        -- Reparto económico personal
        CASE
            WHEN adjustment_type = 'PARTNER_EXPENSE' THEN 0.00
            WHEN adjustment_type = 'MY_EXPENSE'      THEN ROUND(amount, 2)
            WHEN adjustment_type = 'PARTIAL_EXPENSE' 
                THEN -ROUND((ABS(amount) - ABS(COALESCE(adjustment_amount, 0))) * 0.50, 2)
            WHEN account_ownership = 'personal' THEN ROUND(amount, 2)
            WHEN account_ownership = 'common' AND resolved_movement_type IN ('EXPENSE', 'INCOME')
                THEN ROUND(amount * 0.50, 2)
            ELSE 0.00
        END AS personal_amount,

        CASE
            WHEN adjustment_type = 'PARTNER_EXPENSE' THEN 0.00
            WHEN adjustment_type = 'MY_EXPENSE'      THEN 1.00
            WHEN account_ownership = 'common'        THEN 0.50
            ELSE 1.00
        END AS personal_share_pct,

        -- P&L riguroso
        CASE
            WHEN category_is_pnl = FALSE THEN FALSE
            WHEN resolved_movement_type = 'TRANSFER' THEN FALSE
            WHEN transaction_nature IN ('CARD_SETTLEMENT', 'INTERNAL_TRANSFER', 'PARTNER_CONTRIBUTION') THEN FALSE
            ELSE TRUE
        END AS is_pnl,

        -- Gasto compartido
        CASE
            WHEN category_is_pnl = FALSE THEN FALSE
            WHEN resolved_movement_type = 'TRANSFER' THEN FALSE
            WHEN adjustment_type IN ('PARTNER_EXPENSE', 'MY_EXPENSE') THEN FALSE
            WHEN adjustment_type = 'PARTIAL_EXPENSE' THEN TRUE
            WHEN account_ownership = 'common' THEN TRUE
            ELSE FALSE
        END AS is_shared,

        -- Auditoría
        adjustment_type,
        adjustment_amount,
        adjustment_reason,
        source_row_id,
        loaded_at

    FROM with_category
)

SELECT * FROM final
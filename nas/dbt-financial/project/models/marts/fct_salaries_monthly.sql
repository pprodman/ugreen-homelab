{{ config(
    tags = ['mart', 'finance', 'income']
) }}

WITH source_data AS (
    SELECT * FROM {{ ref('fct_transactions') }}
    WHERE category_id IN ('ING_NOMINA', 'ING_PRESTACIONES', 'ING_INDEMNIZACION')
)

SELECT
    accrual_month,
    EXTRACT(YEAR FROM accrual_month)::INT AS year,
    EXTRACT(MONTH FROM accrual_month)::INT AS month,

    -- Desglose por pagadores
    ROUND(SUM(CASE WHEN category_id = 'ING_NOMINA' AND merchant ILIKE '%Bridge%' THEN personal_amount ELSE 0.00 END), 2) AS bridge_broker_net,
    ROUND(SUM(CASE WHEN category_id = 'ING_NOMINA' AND merchant ILIKE '%Basetis%' THEN personal_amount ELSE 0.00 END), 2) AS basetis_net,
    ROUND(SUM(CASE WHEN category_id = 'ING_NOMINA' AND merchant NOT ILIKE '%Bridge%' AND merchant NOT ILIKE '%Basetis%' THEN personal_amount ELSE 0.00 END), 2) AS other_employers_net,

    -- Total nóminas de trabajo por cuenta ajena
    ROUND(SUM(CASE WHEN category_id = 'ING_NOMINA' THEN personal_amount ELSE 0.00 END), 2) AS total_nominas_net,

    -- Prestaciones y ayudas públicas
    ROUND(SUM(CASE WHEN category_id = 'ING_PRESTACIONES' THEN personal_amount ELSE 0.00 END), 2) AS inss_prestaciones_net,

    -- Indemnizaciones / FOGASA
    ROUND(SUM(CASE WHEN category_id = 'ING_INDEMNIZACION' THEN personal_amount ELSE 0.00 END), 2) AS fogasa_net,

    -- Total retribución consolidada del mes
    ROUND(SUM(personal_amount), 2) AS total_labor_income_net,

    -- Cantidad de abonos recibidos
    COUNT(*) AS payment_count

FROM source_data
GROUP BY accrual_month
ORDER BY accrual_month DESC
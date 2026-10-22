{{ config(
    tags = ['mart', 'finance', 'salaries']
) }}

WITH monthly_spine AS (
    -- Extrae únicamente un registro por cada primer día de mes dentro de tu rango real
    SELECT DISTINCT start_of_month, year, month, year_month
    FROM {{ ref('dim_date') }}
    WHERE start_of_month >= '2021-12-01'::DATE
      AND start_of_month <= CURRENT_DATE
),

devengo_laboral AS (
    SELECT
        personal_amount,
        merchant,
        category_id,
        CASE
            WHEN EXTRACT(DAY FROM value_date) <= 16 
                THEN (DATE_TRUNC('month', value_date) - INTERVAL '1 month')::DATE
            ELSE DATE_TRUNC('month', value_date)::DATE
        END AS accrual_date
    FROM {{ ref('fct_transactions') }}
    WHERE category_id IN ('ING_NOMINA', 'ING_PRESTACIONES')
),

aggregated_salaries AS (
    SELECT
        accrual_date,
        COALESCE(
            MAX(CASE WHEN category_id = 'ING_NOMINA' THEN merchant END),
            'INSS'
        ) AS empresa,
        ROUND(SUM(CASE WHEN category_id = 'ING_NOMINA' THEN personal_amount ELSE 0.00 END), 2) AS importe_nomina,
        ROUND(SUM(CASE WHEN category_id = 'ING_PRESTACIONES' THEN personal_amount ELSE 0.00 END), 2) AS importe_prestacion,
        ROUND(SUM(personal_amount), 2) AS importe_total
    FROM devengo_laboral
    GROUP BY accrual_date
)

SELECT
    s.start_of_month AS fecha,
    s.year_month AS periodo,
    s.year,
    s.month,
    COALESCE(a.empresa, '-') AS empresa,
    COALESCE(a.importe_nomina, 0.00) AS importe_nomina,
    COALESCE(a.importe_prestacion, 0.00) AS importe_prestacion,
    COALESCE(a.importe_total, 0.00) AS importe_total
FROM monthly_spine s
LEFT JOIN aggregated_salaries a
    ON s.start_of_month = a.accrual_date
ORDER BY s.start_of_month DESC
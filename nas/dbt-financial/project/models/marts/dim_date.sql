{{ config(
    tags = ['dimension', 'core']
) }}

WITH date_spine AS (
    SELECT 
        datum::DATE AS date_day
    FROM generate_series(
        '2020-01-01'::DATE,
        '2030-12-31'::DATE,
        '1 day'::INTERVAL
    ) AS datum
)

SELECT
    date_day AS date_key,
    EXTRACT(YEAR FROM date_day)::INT AS year,
    EXTRACT(MONTH FROM date_day)::INT AS month,
    EXTRACT(DAY FROM date_day)::INT AS day,
    EXTRACT(QUARTER FROM date_day)::INT AS quarter,
    EXTRACT(ISODOW FROM date_day)::INT AS day_of_week,

    -- First and last day of the month (ideal for aggregations and relationships)
    DATE_TRUNC('month', date_day)::DATE AS start_of_month,
    (DATE_TRUNC('month', date_day) + INTERVAL '1 month - 1 day')::DATE AS end_of_month,

    -- Display formats
    TO_CHAR(date_day, 'YYYY-MM') AS year_month,
    TO_CHAR(date_day, 'Mon YYYY') AS month_year,        -- e.g., 'Jan 2026'
    TO_CHAR(date_day, 'FMMonth') AS month_name,         -- e.g., 'January'
    TO_CHAR(date_day, 'FMDay') AS day_name,             -- e.g., 'Monday'
    'Q' || EXTRACT(QUARTER FROM date_day)::TEXT AS quarter_name,

    -- Analytical flags
    CASE 
        WHEN EXTRACT(ISODOW FROM date_day) IN (6, 7) THEN TRUE 
        ELSE FALSE 
    END AS is_weekend

FROM date_spine
ORDER BY date_key ASC
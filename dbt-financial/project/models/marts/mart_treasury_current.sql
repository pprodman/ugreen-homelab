{{ config(materialized='view') }}

WITH latest_account_balances AS (
    SELECT
        account_id,
        bank,
        account_type,
        account_ownership,
        balance,
        value_date AS last_movement_date,
        ROW_NUMBER() OVER (
            PARTITION BY account_id 
            ORDER BY value_date DESC, source_row_id DESC
        ) AS rn
    FROM {{ ref('int_transactions_unioned') }}
    WHERE balance IS NOT NULL
),

current_balances AS (
    SELECT
        account_id,
        bank,
        account_type,
        account_ownership,
        balance AS total_account_balance,
        -- Tu dinero real según titularidad
        CASE
            WHEN account_ownership = 'common' THEN ROUND(balance / 2.0, 2)
            ELSE balance
        END AS personal_balance,
        last_movement_date
    FROM latest_account_balances
    WHERE rn = 1
),

pending_card_expenses AS (
    -- Gastos de tarjeta del ciclo actual aún no liquidados en cuenta corriente
    SELECT
        account_id,
        account_ownership,
        SUM(amount) AS pending_amount,
        CASE
            WHEN account_ownership = 'common' THEN ROUND(SUM(amount) / 2.0, 2)
            ELSE SUM(amount)
        END AS pending_personal_amount
    FROM {{ ref('int_transactions_unioned') }}
    WHERE account_type = 'card'
      AND value_date > (
          -- Compras posteriores a la última liquidación cargada en cuenta corriente
          SELECT MAX(value_date) 
          FROM {{ ref('int_transactions_unioned') }} 
          WHERE transaction_nature = 'CARD_SETTLEMENT'
      )
    GROUP BY account_id, account_ownership
)

SELECT
    b.account_id,
    b.bank,
    b.account_ownership,
    b.total_account_balance,
    b.personal_balance,
    COALESCE(c.pending_amount, 0.00) AS pending_card_debt,
    (b.personal_balance + COALESCE(c.pending_personal_amount, 0.00)) AS net_personal_liquidity,
    b.last_movement_date
FROM current_balances b
LEFT JOIN pending_card_expenses c
    ON b.account_id = c.account_id
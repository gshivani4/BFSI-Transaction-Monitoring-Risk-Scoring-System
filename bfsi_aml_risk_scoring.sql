CREATE DATABASE bfsi_sql_advanced;
USE bfsi_sql_advanced;

CREATE TABLE customers (
  customer_id INT PRIMARY KEY,
  full_name VARCHAR(100),
  age INT,
  gender CHAR(1),
  city VARCHAR(50),
  account_open_date DATE,
  risk_profile VARCHAR(10)
);

CREATE TABLE accounts (
  account_id BIGINT PRIMARY KEY,
  customer_id INT,
  account_type VARCHAR(20),
  balance DECIMAL(12,2),
  account_status VARCHAR(10),
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE transactions (
  transaction_id BIGINT PRIMARY KEY,
  account_id BIGINT,
  transaction_date TIMESTAMP,
  transaction_type VARCHAR(10),
  amount DECIMAL(12,2),
  channel VARCHAR(20),
  merchant_category VARCHAR(50),
  is_flagged CHAR(1),
  customer_id INT,
  FOREIGN KEY (account_id) REFERENCES accounts(account_id),
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

SELECT
  account_id,
  transaction_date,
  transaction_type,
  amount,
  SUM(
    CASE WHEN transaction_type='Credit'
         THEN amount ELSE -amount END
  ) OVER (
    PARTITION BY account_id
    ORDER BY transaction_date
  ) AS running_balance
FROM transactions;

SELECT COUNT(*) FROM customers;

SET FOREIGN_KEY_CHECKS = 0;

TRUNCATE TABLE transactions;
TRUNCATE TABLE accounts;

SET FOREIGN_KEY_CHECKS = 1;

SELECT COUNT(*) FROM accounts;
SELECT COUNT(*) FROM transactions;

SELECT
  account_id,
  transaction_date,
  transaction_type,
  amount,
  SUM(
    CASE WHEN transaction_type='Credit'
         THEN amount ELSE -amount END
  ) OVER (
    PARTITION BY account_id
    ORDER BY transaction_date
  ) AS running_balance
FROM transactions;

SELECT
  MIN(time_gap_seconds) AS min_gap_seconds
FROM (
  SELECT
    TIMESTAMPDIFF(
      SECOND,
      LAG(transaction_date) OVER (
        PARTITION BY account_id
        ORDER BY transaction_date
      ),
      transaction_date
    ) AS time_gap_seconds
  FROM transactions
) t
WHERE time_gap_seconds IS NOT NULL;

SELECT
  account_id,
  transaction_id,
  transaction_date,
  time_gap_seconds
FROM (
  SELECT
    account_id,
    transaction_id,
    transaction_date,
    TIMESTAMPDIFF(
      SECOND,
      LAG(transaction_date) OVER (
        PARTITION BY account_id
        ORDER BY transaction_date
      ),
      transaction_date
    ) AS time_gap_seconds
  FROM transactions
) t
WHERE time_gap_seconds IS NOT NULL
  AND time_gap_seconds < 1200;  -- 20 minutes


SELECT
  account_id,
  SUM(CASE WHEN transaction_type='Debit' THEN amount END) /
  NULLIF(SUM(CASE WHEN transaction_type='Credit' THEN amount END), 0)
  AS debit_credit_ratio
FROM transactions
GROUP BY account_id;

SELECT
  customer_id,
  SUM(amount) AS total_amount,
  ROUND(
    SUM(amount) * 100.0 /
    SUM(SUM(amount)) OVER (), 2
  ) AS pct_of_bank_volume
FROM transactions
GROUP BY customer_id;

SELECT COUNT(*) 
FROM transactions
WHERE amount > 75000;

SELECT
  account_id,
  DATE(transaction_date) AS txn_date,
  COUNT(*) AS txns_that_day
FROM transactions
GROUP BY account_id, DATE(transaction_date)
HAVING COUNT(*) > 1;


WITH RECURSIVE txn_streak AS (
  SELECT
    account_id,
    DATE(transaction_date) AS txn_date,
    amount,
    1 AS streak
  FROM transactions
  WHERE amount > 75000

  UNION ALL

  SELECT
    t.account_id,
    DATE(t.transaction_date),
    t.amount,
    s.streak + 1
  FROM transactions t
  JOIN txn_streak s
    ON t.account_id = s.account_id
   AND DATE(t.transaction_date) = s.txn_date + INTERVAL 1 DAY
  WHERE t.amount > 75000
)
SELECT
  account_id,
  MAX(streak) AS max_streak
FROM txn_streak
GROUP BY account_id
ORDER BY max_streak DESC;

SELECT
  account_id,
  MAX(transaction_date) AS last_txn_date
FROM transactions
GROUP BY account_id
HAVING MAX(transaction_date) <
       CURRENT_DATE - INTERVAL 90 DAY;

SELECT
  MAX(txn_count) AS max_txns,
  AVG(txn_count) AS avg_txns
FROM (
  SELECT account_id, COUNT(*) AS txn_count
  FROM transactions
  GROUP BY account_id
) t;

SELECT
  MAX(flagged_txns) AS max_flagged
FROM (
  SELECT
    account_id,
    SUM(CASE WHEN is_flagged='Y' THEN 1 ELSE 0 END) AS flagged_txns
  FROM transactions
  GROUP BY account_id
) t;

WITH acct_stats AS (
  SELECT
    account_id,
    COUNT(*) AS txn_count,
    SUM(amount) AS total_amount,
    SUM(CASE WHEN is_flagged='Y' THEN 1 ELSE 0 END) AS flagged_txns
  FROM transactions
  GROUP BY account_id
)
SELECT
  account_id,
  txn_count,
  total_amount,
  flagged_txns,
  (flagged_txns * 3) +
  (CASE WHEN txn_count > 15 THEN 2 ELSE 0 END) +
  (CASE WHEN total_amount > 200000 THEN 1 ELSE 0 END) AS risk_score
FROM acct_stats
ORDER BY risk_score DESC
LIMIT 10;

-- Chronos Billing - Clean Database Schema
CREATE SCHEMA IF NOT EXISTS public;
SET search_path TO public;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- ============================================================
-- 1. Core master tables
-- ============================================================
CREATE TABLE products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL
);
CREATE TABLE accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_account_id uuid REFERENCES accounts(id) ON DELETE
  SET NULL,
    name text NOT NULL,
    timezone text NOT NULL DEFAULT 'UTC',
    status text NOT NULL,
    CONSTRAINT accounts_parent_check CHECK (
      parent_account_id IS NULL
      OR parent_account_id <> id
    ),
    CONSTRAINT accounts_status_check CHECK (
      status IN ('Active', 'Inactive', 'Suspended', 'Archived')
    )
);
CREATE TABLE billable_metrics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  event_name text NOT NULL,
  property_key text,
  aggregation_type text NOT NULL,
  group_keys text [],
  sql_definition text
);
-- ============================================================
-- 2. Pricing model
-- ============================================================
CREATE TABLE rate_cards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE
);
CREATE TABLE prices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rate_card_id uuid NOT NULL REFERENCES rate_cards(id) ON DELETE CASCADE,
  metric_id uuid NOT NULL REFERENCES billable_metrics(id) ON DELETE CASCADE,
  pricing_model text NOT NULL,
  effective_start timestamp with time zone NOT NULL,
  effective_end timestamp with time zone,
  CONSTRAINT prices_date_check CHECK (
    effective_end IS NULL
    OR effective_start < effective_end
  )
);
CREATE TABLE price_dimensions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  price_id uuid NOT NULL REFERENCES prices(id) ON DELETE CASCADE,
  dimension_key text NOT NULL,
  dimension_value text NOT NULL
);
CREATE TABLE price_tiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  price_id uuid NOT NULL REFERENCES prices(id) ON DELETE CASCADE,
  first_unit numeric NOT NULL DEFAULT 0,
  last_unit numeric,
  unit_amount numeric(18, 2) NOT NULL DEFAULT 0,
  flat_amount numeric(18, 2) NOT NULL DEFAULT 0,
  CONSTRAINT tiers_unique_start UNIQUE (price_id, first_unit),
  CONSTRAINT tiers_unit_check CHECK (
    first_unit >= 0
    AND unit_amount >= 0
    AND flat_amount >= 0
    AND (
      last_unit IS NULL
      OR first_unit <= last_unit
    )
  )
);
-- ============================================================
-- 3. Subscription, usage, and billing records
-- ============================================================
CREATE TABLE subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  rate_card_id uuid NOT NULL REFERENCES rate_cards(id) ON DELETE CASCADE,
  billing_interval text NOT NULL,
  current_period_start timestamp with time zone NOT NULL,
  current_period_end timestamp with time zone NOT NULL,
  status text NOT NULL,
  CONSTRAINT subs_status_check CHECK (
    status IN ('Active', 'Canceled', 'Past_Due', 'Trial')
  )
);
CREATE TABLE usage_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  idempotency_key text NOT NULL UNIQUE,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  event_name text NOT NULL,
  timestamp timestamp with time zone NOT NULL,
  properties jsonb DEFAULT '{}'::jsonb,
  ingested_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE usage_events_archive (
  id uuid PRIMARY KEY,
  idempotency_key text,
  account_id uuid,
  event_name text,
  timestamp timestamp with time zone,
  properties jsonb,
  ingested_at timestamp with time zone
);
CREATE TABLE invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  subtotal numeric(18, 2) NOT NULL DEFAULT 0,
  total_amount numeric(18, 2) NOT NULL DEFAULT 0,
  status text NOT NULL,
  billing_period_start timestamp with time zone,
  billing_period_end timestamp with time zone,
  CONSTRAINT invoice_amount_check CHECK (
    subtotal >= 0
    AND total_amount >= 0
  ),
  CONSTRAINT invoices_status_check CHECK (
    status IN ('Draft', 'Open', 'Paid', 'Void', 'Uncollectible')
  )
);
CREATE TABLE invoice_line_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id uuid NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  metric_id uuid NOT NULL REFERENCES billable_metrics(id) ON DELETE CASCADE,
  quantity numeric NOT NULL DEFAULT 0,
  amount numeric(18, 2) NOT NULL DEFAULT 0,
  CONSTRAINT line_item_amount_check CHECK (
    amount >= 0
    AND quantity >= 0
  )
);
CREATE TABLE credit_ledgers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  transaction_type text NOT NULL,
  amount numeric(18, 2) NOT NULL DEFAULT 0,
  running_balance numeric(18, 2) NOT NULL DEFAULT 0,
  reference_id text,
  reference_type varchar(50) NOT NULL,
  currency varchar(3) NOT NULL DEFAULT 'KRW',
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT credit_ledgers_amount_check CHECK (amount >= 0),
  CONSTRAINT credit_ledgers_currency_check CHECK (currency ~ '^[A-Z]{3}$')
);
CREATE UNIQUE INDEX invoices_account_billing_period_key ON invoices (account_id, billing_period_start)
WHERE billing_period_start IS NOT NULL;
-- ============================================================
-- 4. Views
-- ============================================================
CREATE OR REPLACE VIEW v_dashboard_events AS
SELECT id,
  account_id,
  timestamp,
  properties->>'endpoint' AS endpoint,
  (properties->>'tokens_used')::numeric AS tokens_used,
  (properties->>'is_flagged_anomaly')::boolean AS is_flagged_anomaly
FROM usage_events;
CREATE OR REPLACE VIEW v_usage_anomalies AS
SELECT id,
  account_id,
  event_name,
  timestamp,
  properties->>'endpoint' AS endpoint,
  properties->>'region' AS region,
  (properties->>'tokens_used')::numeric AS tokens_used,
  ((properties->>'tokens_used')::numeric - 1000) AS over_threshold_by,
  (properties->>'is_flagged_anomaly')::boolean AS is_flagged_anomaly,
  (properties->>'status_code')::integer AS status_code,
  ingested_at
FROM usage_events
WHERE properties ? 'tokens_used'
  AND properties->>'tokens_used' ~ '^[0-9]+(\.[0-9]+)?$'
  AND (properties->>'tokens_used')::numeric >= 1000;
-- ============================================================
-- 5. Billing function
-- ============================================================
CREATE OR REPLACE FUNCTION generate_monthly_invoice(p_account_id uuid, p_target_month date) RETURNS json LANGUAGE plpgsql AS $$
DECLARE v_account_timezone text;
v_start_time timestamp with time zone;
v_end_time timestamp with time zone;
v_rate_card_id uuid;
v_rate_card_count integer;
v_total_amount numeric(18, 2);
v_charges jsonb;
v_invoice_id uuid;
v_existing_invoice uuid;
v_current_balance numeric(18, 2);
BEGIN PERFORM pg_advisory_xact_lock(hashtext(p_account_id::text)::bigint);
SELECT timezone INTO v_account_timezone
FROM accounts
WHERE id = p_account_id;
IF v_account_timezone IS NULL THEN RAISE EXCEPTION '계정을 찾을 수 없습니다. (Account ID: %)',
p_account_id;
END IF;
v_start_time := date_trunc('month', p_target_month::timestamp) AT TIME ZONE v_account_timezone;
v_end_time := v_start_time + interval '1 month';
SELECT id INTO v_existing_invoice
FROM invoices
WHERE account_id = p_account_id
  AND billing_period_start = v_start_time;
IF v_existing_invoice IS NOT NULL THEN RAISE EXCEPTION '해당 월의 청구서가 이미 존재합니다. (Invoice ID: %)',
v_existing_invoice;
END IF;
SELECT COUNT(DISTINCT rate_card_id),
  (ARRAY_AGG(DISTINCT rate_card_id)) [1] INTO v_rate_card_count,
  v_rate_card_id
FROM subscriptions
WHERE account_id = p_account_id
  AND status = 'Active'
  AND current_period_start < v_end_time
  AND current_period_end > v_start_time;
IF v_rate_card_count = 0 THEN RAISE EXCEPTION '해당 월에 활성 구독이 없습니다. (Account ID: %, Period Start: %)',
p_account_id,
v_start_time;
END IF;
IF v_rate_card_count > 1 THEN RAISE EXCEPTION '해당 월에 여러 Rate Card가 활성화되어 정산할 수 없습니다. (Account ID: %, Period Start: %)',
p_account_id,
v_start_time;
END IF;
WITH token_usage AS (
  SELECT p.id AS price_id,
    p.metric_id,
    CEIL(
      SUM((ue.properties->>'tokens_used')::numeric) / 1000.0
    ) AS quantity
  FROM usage_events ue
    JOIN price_dimensions pd ON pd.dimension_key = 'endpoint'
    AND pd.dimension_value = ue.properties->>'endpoint'
    JOIN prices p ON p.id = pd.price_id
    AND p.rate_card_id = v_rate_card_id
    AND ue.timestamp >= p.effective_start
    AND (
      p.effective_end IS NULL
      OR ue.timestamp < p.effective_end
    )
    JOIN billable_metrics bm ON bm.id = p.metric_id
    AND bm.event_name = ue.event_name
    AND bm.property_key = 'tokens_used'
    AND bm.aggregation_type = 'sum'
  WHERE ue.account_id = p_account_id
    AND ue.timestamp >= v_start_time
    AND ue.timestamp < v_end_time
    AND ue.properties ? 'tokens_used'
    AND ue.properties->>'tokens_used' ~ '^[0-9]+(\.[0-9]+)?$'
  GROUP BY p.id,
    p.metric_id
),
request_usage AS (
  SELECT p.id AS price_id,
    p.metric_id,
    COUNT(*)::numeric AS quantity
  FROM usage_events ue
    JOIN price_dimensions pd ON pd.dimension_key = 'endpoint'
    AND pd.dimension_value = '*'
    JOIN prices p ON p.id = pd.price_id
    AND p.rate_card_id = v_rate_card_id
    AND ue.timestamp >= p.effective_start
    AND (
      p.effective_end IS NULL
      OR ue.timestamp < p.effective_end
    )
    JOIN billable_metrics bm ON bm.id = p.metric_id
    AND bm.event_name = ue.event_name
    AND bm.property_key IS NULL
    AND bm.aggregation_type = 'count'
  WHERE ue.account_id = p_account_id
    AND ue.timestamp >= v_start_time
    AND ue.timestamp < v_end_time
  GROUP BY p.id,
    p.metric_id
),
aggregated_usage AS (
  SELECT price_id,
    metric_id,
    quantity
  FROM token_usage
  UNION ALL
  SELECT price_id,
    metric_id,
    quantity
  FROM request_usage
),
tier_charges AS (
  SELECT au.price_id,
    au.metric_id,
    au.quantity,
    CASE
      WHEN pt.last_unit IS NULL
      AND au.quantity >= pt.first_unit THEN (au.quantity - pt.first_unit + 1) * pt.unit_amount + COALESCE(pt.flat_amount, 0)
      WHEN pt.last_unit IS NOT NULL
      AND au.quantity > pt.last_unit THEN (pt.last_unit - pt.first_unit + 1) * pt.unit_amount + COALESCE(pt.flat_amount, 0)
      WHEN pt.last_unit IS NOT NULL
      AND au.quantity >= pt.first_unit
      AND au.quantity <= pt.last_unit THEN (au.quantity - pt.first_unit + 1) * pt.unit_amount + COALESCE(pt.flat_amount, 0)
      ELSE 0
    END AS amount
  FROM aggregated_usage au
    JOIN price_tiers pt ON pt.price_id = au.price_id
),
charges AS (
  SELECT price_id,
    metric_id,
    quantity,
    ROUND(SUM(amount), 2)::numeric(18, 2) AS amount
  FROM tier_charges
  GROUP BY price_id,
    metric_id,
    quantity
  HAVING ROUND(SUM(amount), 2) > 0
)
SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'price_id',
        price_id,
        'metric_id',
        metric_id,
        'quantity',
        quantity,
        'amount',
        amount
      )
    ),
    '[]'::jsonb
  ),
  COALESCE(ROUND(SUM(amount), 2), 0)::numeric(18, 2) INTO v_charges,
  v_total_amount
FROM charges;
IF v_total_amount = 0 THEN RAISE EXCEPTION '해당 월에 청구할 트래픽 내역이 없거나, 유효한 요금제/구독이 없습니다.';
END IF;
BEGIN
INSERT INTO invoices (
    account_id,
    subtotal,
    total_amount,
    status,
    billing_period_start,
    billing_period_end
  )
VALUES (
    p_account_id,
    v_total_amount,
    v_total_amount,
    'Open',
    v_start_time,
    v_end_time
  )
RETURNING id INTO v_invoice_id;
EXCEPTION
WHEN unique_violation THEN
SELECT id INTO v_existing_invoice
FROM invoices
WHERE account_id = p_account_id
  AND billing_period_start = v_start_time;
RAISE EXCEPTION '해당 월의 청구서가 이미 존재합니다. (Invoice ID: %)',
v_existing_invoice;
END;
INSERT INTO invoice_line_items (
    invoice_id,
    metric_id,
    quantity,
    amount
  )
SELECT v_invoice_id,
  metric_id,
  SUM(quantity),
  ROUND(SUM(amount), 2)
FROM jsonb_to_recordset(v_charges) AS charge(
    price_id uuid,
    metric_id uuid,
    quantity numeric,
    amount numeric
  )
GROUP BY metric_id;
SELECT COALESCE(running_balance, 0) INTO v_current_balance
FROM credit_ledgers
WHERE account_id = p_account_id
ORDER BY created_at DESC,
  id DESC
LIMIT 1;
v_current_balance := COALESCE(v_current_balance, 0);
INSERT INTO credit_ledgers (
    account_id,
    transaction_type,
    amount,
    running_balance,
    reference_type,
    reference_id
  )
VALUES (
    p_account_id,
    'Invoice Settlement',
    v_total_amount,
    v_current_balance - v_total_amount,
    'invoice',
    v_invoice_id::text
  );
RETURN json_build_object(
  'invoice_id',
  v_invoice_id,
  'total_amount',
  v_total_amount,
  'billing_period_start',
  v_start_time,
  'billing_period_end',
  v_end_time,
  'status',
  'success'
);
END;
$$;
-- ============================================================
-- 6. Security policy summary
-- ============================================================
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
CREATE POLICY products_public_read_policy ON products FOR
SELECT USING (true);
GRANT SELECT ON v_dashboard_events TO anon,
  authenticated,
  service_role;
GRANT SELECT ON v_usage_anomalies TO anon,
  authenticated,
  service_role;
GRANT EXECUTE ON FUNCTION generate_monthly_invoice(uuid, date) TO anon,
  authenticated,
  service_role;
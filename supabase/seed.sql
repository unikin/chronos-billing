-- Price catalog seed for the simulator.
-- Billing quantity is intended to be 1,000-token blocks:
-- billable_units = CEIL(tokens_used / 1000.0)
-- Amounts are KRW per 1,000-token block and include a modest platform margin.

INSERT INTO public.products (id, name)
VALUES
  ('11111111-1111-4111-8111-111111111111', 'Chronos AI Usage Billing')
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name;

INSERT INTO public.rate_cards (id, product_id)
VALUES
  ('22222222-2222-4222-8222-222222222222', '11111111-1111-4111-8111-111111111111')
ON CONFLICT (id) DO UPDATE
SET product_id = EXCLUDED.product_id;

INSERT INTO public.billable_metrics (
  id,
  name,
  event_name,
  property_key,
  aggregation_type,
  group_keys,
  sql_definition
)
VALUES
  (
    '33333333-3333-4333-8333-333333333333',
    'API token usage',
    'api_request',
    'tokens_used',
    'sum',
    ARRAY['endpoint', 'region']::text[],
    'SUM((properties->>''tokens_used'')::numeric)'
  ),
  (
    '33333333-3333-4333-8333-333333333334',
    'API request count',
    'api_request',
    NULL,
    'count',
    ARRAY['endpoint', 'region']::text[],
    'COUNT(*)'
  )
ON CONFLICT (id) DO UPDATE
SET
  name = EXCLUDED.name,
  event_name = EXCLUDED.event_name,
  property_key = EXCLUDED.property_key,
  aggregation_type = EXCLUDED.aggregation_type,
  group_keys = EXCLUDED.group_keys,
  sql_definition = EXCLUDED.sql_definition;

INSERT INTO public.prices (
  id,
  rate_card_id,
  metric_id,
  pricing_model,
  effective_start,
  effective_end
)
VALUES
  (
    '44444444-4444-4444-8444-444444444441',
    '22222222-2222-4222-8222-222222222222',
    '33333333-3333-4333-8333-333333333333',
    'graduated',
    '2026-01-01T00:00:00+00:00',
    NULL
  ),
  (
    '44444444-4444-4444-8444-444444444442',
    '22222222-2222-4222-8222-222222222222',
    '33333333-3333-4333-8333-333333333333',
    'graduated',
    '2026-01-01T00:00:00+00:00',
    NULL
  ),
  (
    '44444444-4444-4444-8444-444444444443',
    '22222222-2222-4222-8222-222222222222',
    '33333333-3333-4333-8333-333333333333',
    'graduated',
    '2026-01-01T00:00:00+00:00',
    NULL
  ),
  (
    '44444444-4444-4444-8444-444444444444',
    '22222222-2222-4222-8222-222222222222',
    '33333333-3333-4333-8333-333333333334',
    'graduated',
    '2026-01-01T00:00:00+00:00',
    NULL
  )
ON CONFLICT (id) DO UPDATE
SET
  rate_card_id = EXCLUDED.rate_card_id,
  metric_id = EXCLUDED.metric_id,
  pricing_model = EXCLUDED.pricing_model,
  effective_start = EXCLUDED.effective_start,
  effective_end = EXCLUDED.effective_end;

INSERT INTO public.price_dimensions (id, price_id, dimension_key, dimension_value)
VALUES
  ('55555555-5555-4555-8555-555555555551', '44444444-4444-4444-8444-444444444441', 'endpoint', 'gpt-4-turbo'),
  ('55555555-5555-4555-8555-555555555552', '44444444-4444-4444-8444-444444444442', 'endpoint', 'gpt-3.5-turbo'),
  ('55555555-5555-4555-8555-555555555553', '44444444-4444-4444-8444-444444444443', 'endpoint', 'claude-3-opus'),
  ('55555555-5555-4555-8555-555555555554', '44444444-4444-4444-8444-444444444444', 'endpoint', '*')
ON CONFLICT (id) DO UPDATE
SET
  price_id = EXCLUDED.price_id,
  dimension_key = EXCLUDED.dimension_key,
  dimension_value = EXCLUDED.dimension_value;

INSERT INTO public.price_tiers (
  id,
  price_id,
  first_unit,
  last_unit,
  unit_amount,
  flat_amount
)
VALUES
  -- gpt-4-turbo token blocks: 0 to 1M, 1M to 10M, 10M+ tokens.
  ('66666666-6666-4666-8666-666666666601', '44444444-4444-4444-8444-444444444441', 1, 1000, 30.00, 0.00),
  ('66666666-6666-4666-8666-666666666602', '44444444-4444-4444-8444-444444444441', 1001, 10000, 27.00, 0.00),
  ('66666666-6666-4666-8666-666666666603', '44444444-4444-4444-8444-444444444441', 10001, NULL, 24.00, 0.00),

  -- gpt-3.5-turbo token blocks: low-cost model with volume discounts.
  ('66666666-6666-4666-8666-666666666611', '44444444-4444-4444-8444-444444444442', 1, 1000, 2.00, 0.00),
  ('66666666-6666-4666-8666-666666666612', '44444444-4444-4444-8444-444444444442', 1001, 10000, 1.80, 0.00),
  ('66666666-6666-4666-8666-666666666613', '44444444-4444-4444-8444-444444444442', 10001, NULL, 1.50, 0.00),

  -- claude-3-opus token blocks: premium model pricing.
  ('66666666-6666-4666-8666-666666666621', '44444444-4444-4444-8444-444444444443', 1, 1000, 65.00, 0.00),
  ('66666666-6666-4666-8666-666666666622', '44444444-4444-4444-8444-444444444443', 1001, 10000, 58.00, 0.00),
  ('66666666-6666-4666-8666-666666666623', '44444444-4444-4444-8444-444444444443', 10001, NULL, 52.00, 0.00),

  -- Platform request fee: per API request, separate from token usage.
  ('66666666-6666-4666-8666-666666666631', '44444444-4444-4444-8444-444444444444', 1, 100000, 0.10, 0.00),
  ('66666666-6666-4666-8666-666666666632', '44444444-4444-4444-8444-444444444444', 100001, 1000000, 0.08, 0.00),
  ('66666666-6666-4666-8666-666666666633', '44444444-4444-4444-8444-444444444444', 1000001, NULL, 0.05, 0.00)
ON CONFLICT (id) DO UPDATE
SET
  price_id = EXCLUDED.price_id,
  first_unit = EXCLUDED.first_unit,
  last_unit = EXCLUDED.last_unit,
  unit_amount = EXCLUDED.unit_amount,
  flat_amount = EXCLUDED.flat_amount;

-- Demo account with enough current-month history to validate long-range dashboard
-- grouping and billing settlement behavior. Usage event count is capped at 28
-- so the dashboard remains readable while still spanning multiple days/weeks.

INSERT INTO public.accounts (id, parent_account_id, name, timezone, status)
VALUES
  (
    '77777777-7777-4777-8777-777777777701',
    NULL,
    'Chronos Long Range Demo',
    'Asia/Seoul',
    'Active'
  )
ON CONFLICT (id) DO UPDATE
SET
  parent_account_id = EXCLUDED.parent_account_id,
  name = EXCLUDED.name,
  timezone = EXCLUDED.timezone,
  status = EXCLUDED.status;

INSERT INTO public.subscriptions (
  id,
  account_id,
  rate_card_id,
  billing_interval,
  current_period_start,
  current_period_end,
  status
)
VALUES
  (
    '77777777-7777-4777-8777-777777777711',
    '77777777-7777-4777-8777-777777777701',
    '22222222-2222-4222-8222-222222222222',
    'Monthly',
    '2026-06-01T00:00:00+09:00',
    '2026-07-01T00:00:00+09:00',
    'Active'
  )
ON CONFLICT (id) DO UPDATE
SET
  account_id = EXCLUDED.account_id,
  rate_card_id = EXCLUDED.rate_card_id,
  billing_interval = EXCLUDED.billing_interval,
  current_period_start = EXCLUDED.current_period_start,
  current_period_end = EXCLUDED.current_period_end,
  status = EXCLUDED.status;

INSERT INTO public.usage_events (
  id,
  idempotency_key,
  account_id,
  event_name,
  timestamp,
  properties
)
VALUES
  ('88888888-8888-4888-8888-888888888801', 'seed_long_demo_20260601_001', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-01T10:30:00+09:00', '{"endpoint":"gpt-4-turbo","region":"ap-northeast-2","tokens_used":850,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888802', 'seed_long_demo_20260601_002', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-01T15:45:00+09:00', '{"endpoint":"gpt-3.5-turbo","region":"ap-northeast-2","tokens_used":320,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888803', 'seed_long_demo_20260602_001', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-02T09:20:00+09:00', '{"endpoint":"claude-3-opus","region":"ap-northeast-2","tokens_used":640,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888804', 'seed_long_demo_20260602_002', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-02T18:10:00+09:00', '{"endpoint":"gpt-4-turbo","region":"ap-northeast-2","tokens_used":910,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888805', 'seed_long_demo_20260603_001', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-03T08:00:00+09:00', '{"endpoint":"gpt-3.5-turbo","region":"ap-northeast-2","tokens_used":450,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888806', 'seed_long_demo_20260603_002', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-03T23:30:00+09:00', '{"endpoint":"gpt-4-turbo","region":"ap-northeast-2","tokens_used":1250,"is_flagged_anomaly":true,"status_code":429}'::jsonb),
  ('88888888-8888-4888-8888-888888888807', 'seed_long_demo_20260604_001', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-04T10:15:00+09:00', '{"endpoint":"claude-3-opus","region":"ap-northeast-2","tokens_used":700,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888808', 'seed_long_demo_20260604_002', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-04T21:05:00+09:00', '{"endpoint":"gpt-3.5-turbo","region":"ap-northeast-2","tokens_used":380,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888809', 'seed_long_demo_20260605_001', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-05T11:40:00+09:00', '{"endpoint":"gpt-4-turbo","region":"ap-northeast-2","tokens_used":980,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888810', 'seed_long_demo_20260605_002', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-05T19:50:00+09:00', '{"endpoint":"claude-3-opus","region":"ap-northeast-2","tokens_used":760,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888811', 'seed_long_demo_20260606_001', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-06T07:55:00+09:00', '{"endpoint":"gpt-3.5-turbo","region":"ap-northeast-2","tokens_used":410,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888812', 'seed_long_demo_20260606_002', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-06T22:25:00+09:00', '{"endpoint":"gpt-4-turbo","region":"ap-northeast-2","tokens_used":1020,"is_flagged_anomaly":true,"status_code":429}'::jsonb),
  ('88888888-8888-4888-8888-888888888813', 'seed_long_demo_20260607_001', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-07T12:10:00+09:00', '{"endpoint":"claude-3-opus","region":"ap-northeast-2","tokens_used":830,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888814', 'seed_long_demo_20260607_002', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-07T17:35:00+09:00', '{"endpoint":"gpt-3.5-turbo","region":"ap-northeast-2","tokens_used":360,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888815', 'seed_long_demo_20260608_001', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-08T09:05:00+09:00', '{"endpoint":"gpt-4-turbo","region":"ap-northeast-2","tokens_used":940,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888816', 'seed_long_demo_20260608_002', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-08T20:45:00+09:00', '{"endpoint":"gpt-3.5-turbo","region":"ap-northeast-2","tokens_used":500,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888817', 'seed_long_demo_20260609_001', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-09T13:15:00+09:00', '{"endpoint":"claude-3-opus","region":"ap-northeast-2","tokens_used":690,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888818', 'seed_long_demo_20260609_002', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-09T23:00:00+09:00', '{"endpoint":"gpt-4-turbo","region":"ap-northeast-2","tokens_used":870,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888819', 'seed_long_demo_20260610_001', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-10T08:35:00+09:00', '{"endpoint":"gpt-3.5-turbo","region":"ap-northeast-2","tokens_used":430,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888820', 'seed_long_demo_20260610_002', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-10T16:20:00+09:00', '{"endpoint":"claude-3-opus","region":"ap-northeast-2","tokens_used":780,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888821', 'seed_long_demo_20260611_001', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-11T10:00:00+09:00', '{"endpoint":"gpt-4-turbo","region":"ap-northeast-2","tokens_used":990,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888822', 'seed_long_demo_20260611_002', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-11T18:40:00+09:00', '{"endpoint":"gpt-3.5-turbo","region":"ap-northeast-2","tokens_used":520,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888823', 'seed_long_demo_20260612_001', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-12T06:50:00+09:00', '{"endpoint":"claude-3-opus","region":"ap-northeast-2","tokens_used":810,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888824', 'seed_long_demo_20260612_002', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-12T22:10:00+09:00', '{"endpoint":"gpt-4-turbo","region":"ap-northeast-2","tokens_used":1160,"is_flagged_anomaly":true,"status_code":429}'::jsonb),
  ('88888888-8888-4888-8888-888888888825', 'seed_long_demo_20260613_001', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-13T11:30:00+09:00', '{"endpoint":"gpt-3.5-turbo","region":"ap-northeast-2","tokens_used":470,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888826', 'seed_long_demo_20260613_002', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-13T19:15:00+09:00', '{"endpoint":"claude-3-opus","region":"ap-northeast-2","tokens_used":730,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888827', 'seed_long_demo_20260614_001', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-14T09:45:00+09:00', '{"endpoint":"gpt-4-turbo","region":"ap-northeast-2","tokens_used":900,"is_flagged_anomaly":false,"status_code":200}'::jsonb),
  ('88888888-8888-4888-8888-888888888828', 'seed_long_demo_20260614_002', '77777777-7777-4777-8777-777777777701', 'api_request', '2026-06-14T17:25:00+09:00', '{"endpoint":"gpt-3.5-turbo","region":"ap-northeast-2","tokens_used":540,"is_flagged_anomaly":false,"status_code":200}'::jsonb)
ON CONFLICT (id) DO UPDATE
SET
  idempotency_key = EXCLUDED.idempotency_key,
  account_id = EXCLUDED.account_id,
  event_name = EXCLUDED.event_name,
  timestamp = EXCLUDED.timestamp,
  properties = EXCLUDED.properties;

INSERT INTO public.invoices (
  id,
  account_id,
  subtotal,
  total_amount,
  status,
  billing_period_start,
  billing_period_end
)
VALUES
  (
    '99999999-9999-4999-8999-999999999901',
    '77777777-7777-4777-8777-777777777701',
    702.80,
    702.80,
    'Paid',
    '2026-06-01T00:00:00+09:00',
    '2026-07-01T00:00:00+09:00'
  )
ON CONFLICT (id) DO UPDATE
SET
  account_id = EXCLUDED.account_id,
  subtotal = EXCLUDED.subtotal,
  total_amount = EXCLUDED.total_amount,
  status = EXCLUDED.status,
  billing_period_start = EXCLUDED.billing_period_start,
  billing_period_end = EXCLUDED.billing_period_end;

INSERT INTO public.invoice_line_items (id, invoice_id, metric_id, quantity, amount)
VALUES
  (
    '99999999-9999-4999-8999-999999999911',
    '99999999-9999-4999-8999-999999999901',
    '33333333-3333-4333-8333-333333333333',
    21,
    700.00
  ),
  (
    '99999999-9999-4999-8999-999999999912',
    '99999999-9999-4999-8999-999999999901',
    '33333333-3333-4333-8333-333333333334',
    28,
    2.80
  )
ON CONFLICT (id) DO UPDATE
SET
  invoice_id = EXCLUDED.invoice_id,
  metric_id = EXCLUDED.metric_id,
  quantity = EXCLUDED.quantity,
  amount = EXCLUDED.amount;

INSERT INTO public.credit_ledgers (
  id,
  account_id,
  transaction_type,
  amount,
  running_balance,
  reference_id,
  reference_type,
  currency,
  created_at
)
VALUES
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
    '77777777-7777-4777-8777-777777777701',
    'Credit Grant',
    100000.00,
    100000.00,
    'seed-initial-credit',
    'seed',
    'KRW',
    '2026-06-01T00:00:00+09:00'
  ),
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
    '77777777-7777-4777-8777-777777777701',
    'Invoice Settlement',
    702.80,
    99297.20,
    '99999999-9999-4999-8999-999999999901',
    'invoice',
    'KRW',
    '2026-06-14T23:59:00+09:00'
  )
ON CONFLICT (id) DO UPDATE
SET
  account_id = EXCLUDED.account_id,
  transaction_type = EXCLUDED.transaction_type,
  amount = EXCLUDED.amount,
  running_balance = EXCLUDED.running_balance,
  reference_id = EXCLUDED.reference_id,
  reference_type = EXCLUDED.reference_type,
  currency = EXCLUDED.currency,
  created_at = EXCLUDED.created_at;

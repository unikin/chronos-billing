CREATE OR REPLACE VIEW public.v_usage_anomalies AS
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
FROM public.usage_events
WHERE properties ? 'tokens_used'
  AND properties->>'tokens_used' ~ '^[0-9]+(\.[0-9]+)?$'
  AND (properties->>'tokens_used')::numeric >= 1000;
GRANT ALL ON TABLE public.v_usage_anomalies TO anon;
GRANT ALL ON TABLE public.v_usage_anomalies TO authenticated;
GRANT ALL ON TABLE public.v_usage_anomalies TO service_role;
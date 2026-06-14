CREATE OR REPLACE VIEW v_dashboard_events AS
SELECT 
    id,
    account_id,
    timestamp,
    properties->>'endpoint' AS endpoint,
    (properties->>'tokens_used')::NUMERIC AS tokens_used,
    (properties->>'is_flagged_anomaly')::BOOLEAN AS is_flagged_anomaly
FROM usage_events;
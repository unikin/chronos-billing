ALTER TABLE public.invoices
ADD COLUMN IF NOT EXISTS billing_period_start timestamp with time zone,
ADD COLUMN IF NOT EXISTS billing_period_end timestamp with time zone;

CREATE UNIQUE INDEX IF NOT EXISTS invoices_account_billing_period_key
ON public.invoices (account_id, billing_period_start)
WHERE billing_period_start IS NOT NULL;

UPDATE public.price_tiers
SET first_unit = 1
WHERE first_unit = 0;

CREATE OR REPLACE FUNCTION public.generate_monthly_invoice(
  p_account_id uuid,
  p_target_month date
)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
  v_account_timezone text;
  v_start_time timestamp with time zone;
  v_end_time timestamp with time zone;
  v_rate_card_id uuid;
  v_rate_card_count integer;
  v_total_amount numeric(18,2);
  v_charges jsonb;
  v_invoice_id uuid;
  v_existing_invoice uuid;
  v_current_balance numeric(18,2);
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext(p_account_id::text)::bigint);

  SELECT timezone
  INTO v_account_timezone
  FROM public.accounts
  WHERE id = p_account_id;

  IF v_account_timezone IS NULL THEN
    RAISE EXCEPTION '계정을 찾을 수 없습니다. (Account ID: %)', p_account_id;
  END IF;

  v_start_time := date_trunc('month', p_target_month::timestamp) AT TIME ZONE v_account_timezone;
  v_end_time := v_start_time + interval '1 month';

  SELECT id
  INTO v_existing_invoice
  FROM public.invoices
  WHERE account_id = p_account_id
    AND billing_period_start = v_start_time;

  IF v_existing_invoice IS NOT NULL THEN
    RAISE EXCEPTION '해당 월의 청구서가 이미 존재합니다. (Invoice ID: %)', v_existing_invoice;
  END IF;

  SELECT COUNT(DISTINCT rate_card_id), (ARRAY_AGG(DISTINCT rate_card_id))[1]
  INTO v_rate_card_count, v_rate_card_id
  FROM public.subscriptions
  WHERE account_id = p_account_id
    AND status = 'Active'
    AND current_period_start < v_end_time
    AND current_period_end > v_start_time;

  IF v_rate_card_count = 0 THEN
    RAISE EXCEPTION '해당 월에 활성 구독이 없습니다. (Account ID: %, Period Start: %)', p_account_id, v_start_time;
  END IF;

  IF v_rate_card_count > 1 THEN
    RAISE EXCEPTION '해당 월에 여러 Rate Card가 활성화되어 정산할 수 없습니다. (Account ID: %, Period Start: %)', p_account_id, v_start_time;
  END IF;

  WITH token_usage AS (
    SELECT
      p.id AS price_id,
      p.metric_id,
      CEIL(SUM((ue.properties->>'tokens_used')::numeric) / 1000.0) AS quantity
    FROM public.usage_events ue
    JOIN public.price_dimensions pd
      ON pd.dimension_key = 'endpoint'
     AND pd.dimension_value = ue.properties->>'endpoint'
    JOIN public.prices p
      ON p.id = pd.price_id
     AND p.rate_card_id = v_rate_card_id
     AND ue.timestamp >= p.effective_start
     AND (p.effective_end IS NULL OR ue.timestamp < p.effective_end)
    JOIN public.billable_metrics bm
      ON bm.id = p.metric_id
     AND bm.event_name = ue.event_name
     AND bm.property_key = 'tokens_used'
     AND bm.aggregation_type = 'sum'
    WHERE ue.account_id = p_account_id
      AND ue.timestamp >= v_start_time
      AND ue.timestamp < v_end_time
      AND ue.properties ? 'tokens_used'
      AND ue.properties->>'tokens_used' ~ '^[0-9]+(\.[0-9]+)?$'
    GROUP BY p.id, p.metric_id
  ),
  request_usage AS (
    SELECT
      p.id AS price_id,
      p.metric_id,
      COUNT(*)::numeric AS quantity
    FROM public.usage_events ue
    JOIN public.price_dimensions pd
      ON pd.dimension_key = 'endpoint'
     AND pd.dimension_value = '*'
    JOIN public.prices p
      ON p.id = pd.price_id
     AND p.rate_card_id = v_rate_card_id
     AND ue.timestamp >= p.effective_start
     AND (p.effective_end IS NULL OR ue.timestamp < p.effective_end)
    JOIN public.billable_metrics bm
      ON bm.id = p.metric_id
     AND bm.event_name = ue.event_name
     AND bm.property_key IS NULL
     AND bm.aggregation_type = 'count'
    WHERE ue.account_id = p_account_id
      AND ue.timestamp >= v_start_time
      AND ue.timestamp < v_end_time
    GROUP BY p.id, p.metric_id
  ),
  aggregated_usage AS (
    SELECT price_id, metric_id, quantity FROM token_usage
    UNION ALL
    SELECT price_id, metric_id, quantity FROM request_usage
  ),
  tier_charges AS (
    SELECT
      au.price_id,
      au.metric_id,
      au.quantity,
      CASE
        WHEN pt.last_unit IS NULL AND au.quantity >= pt.first_unit
          THEN (au.quantity - pt.first_unit + 1) * pt.unit_amount + COALESCE(pt.flat_amount, 0)
        WHEN pt.last_unit IS NOT NULL AND au.quantity > pt.last_unit
          THEN (pt.last_unit - pt.first_unit + 1) * pt.unit_amount + COALESCE(pt.flat_amount, 0)
        WHEN pt.last_unit IS NOT NULL AND au.quantity >= pt.first_unit AND au.quantity <= pt.last_unit
          THEN (au.quantity - pt.first_unit + 1) * pt.unit_amount + COALESCE(pt.flat_amount, 0)
        ELSE 0
      END AS amount
    FROM aggregated_usage au
    JOIN public.price_tiers pt
      ON pt.price_id = au.price_id
  ),
  charges AS (
    SELECT
      price_id,
      metric_id,
      quantity,
      ROUND(SUM(amount), 2)::numeric(18,2) AS amount
    FROM tier_charges
    GROUP BY price_id, metric_id, quantity
    HAVING ROUND(SUM(amount), 2) > 0
  )
  SELECT
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'price_id', price_id,
          'metric_id', metric_id,
          'quantity', quantity,
          'amount', amount
        )
      ),
      '[]'::jsonb
    ),
    COALESCE(ROUND(SUM(amount), 2), 0)::numeric(18,2)
  INTO v_charges, v_total_amount
  FROM charges;

  IF v_total_amount = 0 THEN
    RAISE EXCEPTION '해당 월에 청구할 트래픽 내역이 없거나, 유효한 요금제/구독이 없습니다.';
  END IF;

  BEGIN
    INSERT INTO public.invoices (
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
      SELECT id
      INTO v_existing_invoice
      FROM public.invoices
      WHERE account_id = p_account_id
        AND billing_period_start = v_start_time;

      RAISE EXCEPTION '해당 월의 청구서가 이미 존재합니다. (Invoice ID: %)', v_existing_invoice;
  END;

  INSERT INTO public.invoice_line_items (
    invoice_id,
    metric_id,
    quantity,
    amount
  )
  SELECT
    v_invoice_id,
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

  SELECT COALESCE(running_balance, 0)
  INTO v_current_balance
  FROM public.credit_ledgers
  WHERE account_id = p_account_id
  ORDER BY created_at DESC, id DESC
  LIMIT 1;

  v_current_balance := COALESCE(v_current_balance, 0);

  INSERT INTO public.credit_ledgers (
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
    'invoice_id', v_invoice_id,
    'total_amount', v_total_amount,
    'billing_period_start', v_start_time,
    'billing_period_end', v_end_time,
    'status', 'success'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.generate_monthly_invoice(uuid, date) TO anon;
GRANT EXECUTE ON FUNCTION public.generate_monthly_invoice(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_monthly_invoice(uuid, date) TO service_role;

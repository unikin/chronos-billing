SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;
CREATE SCHEMA IF NOT EXISTS "extensions";
ALTER SCHEMA "extensions" OWNER TO "postgres";
CREATE SCHEMA IF NOT EXISTS "graphql";
ALTER SCHEMA "graphql" OWNER TO "supabase_admin";
CREATE SCHEMA IF NOT EXISTS "public";
ALTER SCHEMA "public" OWNER TO "pg_database_owner";
COMMENT ON SCHEMA "public" IS 'standard public schema';
CREATE SCHEMA IF NOT EXISTS "vault";
ALTER SCHEMA "vault" OWNER TO "supabase_admin";
CREATE OR REPLACE FUNCTION "extensions"."grant_pg_cron_access"() RETURNS "event_trigger" LANGUAGE "plpgsql" AS $$ BEGIN IF EXISTS (
        SELECT
        FROM pg_event_trigger_ddl_commands() AS ev
            JOIN pg_extension AS ext ON ev.objid = ext.oid
        WHERE ext.extname = 'pg_cron'
    ) THEN
grant usage on schema cron to postgres with
grant option;
alter default privileges in schema cron
grant all on tables to postgres with
grant option;
alter default privileges in schema cron
grant all on functions to postgres with
grant option;
alter default privileges in schema cron
grant all on sequences to postgres with
grant option;
alter default privileges for user supabase_admin in schema cron
grant all on sequences to postgres with
grant option;
alter default privileges for user supabase_admin in schema cron
grant all on tables to postgres with
grant option;
alter default privileges for user supabase_admin in schema cron
grant all on functions to postgres with
grant option;
grant all privileges on all tables in schema cron to postgres with
grant option;
revoke all on table cron.job
from postgres;
grant select on table cron.job to postgres with
grant option;
END IF;
END;
$$;
ALTER FUNCTION "extensions"."grant_pg_cron_access"() OWNER TO "supabase_admin";
COMMENT ON FUNCTION "extensions"."grant_pg_cron_access"() IS 'Grants access to pg_cron';
CREATE OR REPLACE FUNCTION "extensions"."grant_pg_graphql_access"() RETURNS "event_trigger" LANGUAGE "plpgsql" AS $_$
DECLARE func_is_graphql_resolve bool;
BEGIN func_is_graphql_resolve = (
    SELECT n.proname = 'resolve'
    FROM pg_event_trigger_ddl_commands() AS ev
        LEFT JOIN pg_catalog.pg_proc AS n ON ev.objid = n.oid
);
IF func_is_graphql_resolve THEN -- Update public wrapper to pass all arguments through to the pg_graphql resolve func
DROP FUNCTION IF EXISTS graphql_public.graphql;
create or replace function graphql_public.graphql(
        "operationName" text default null,
        query text default null,
        variables jsonb default null,
        extensions jsonb default null
    ) returns jsonb language sql as $$
select graphql.resolve(
        query := query,
        variables := coalesce(variables, '{}'),
        "operationName" := "operationName",
        extensions := extensions
    );
$$;
-- This hook executes when `graphql.resolve` is created. That is not necessarily the last
-- function in the extension so we need to grant permissions on existing entities AND
-- update default permissions to any others that are created after `graphql.resolve`
grant usage on schema graphql to postgres,
    anon,
    authenticated,
    service_role;
grant select on all tables in schema graphql to postgres,
    anon,
    authenticated,
    service_role;
grant execute on all functions in schema graphql to postgres,
    anon,
    authenticated,
    service_role;
grant all on all sequences in schema graphql to postgres,
    anon,
    authenticated,
    service_role;
alter default privileges in schema graphql
grant all on tables to postgres,
    anon,
    authenticated,
    service_role;
alter default privileges in schema graphql
grant all on functions to postgres,
    anon,
    authenticated,
    service_role;
alter default privileges in schema graphql
grant all on sequences to postgres,
    anon,
    authenticated,
    service_role;
-- Allow postgres role to allow granting usage on graphql and graphql_public schemas to custom roles
grant usage on schema graphql_public to postgres with
grant option;
grant usage on schema graphql to postgres with
grant option;
END IF;
END;
$_$;
ALTER FUNCTION "extensions"."grant_pg_graphql_access"() OWNER TO "supabase_admin";
COMMENT ON FUNCTION "extensions"."grant_pg_graphql_access"() IS 'Grants access to pg_graphql';
CREATE OR REPLACE FUNCTION "extensions"."grant_pg_net_access"() RETURNS "event_trigger" LANGUAGE "plpgsql" AS $$ BEGIN IF EXISTS (
        SELECT 1
        FROM pg_event_trigger_ddl_commands() AS ev
            JOIN pg_extension AS ext ON ev.objid = ext.oid
        WHERE ext.extname = 'pg_net'
    ) THEN
GRANT USAGE ON SCHEMA net TO supabase_functions_admin,
    postgres,
    anon,
    authenticated,
    service_role;
ALTER function net.http_get(
    url text,
    params jsonb,
    headers jsonb,
    timeout_milliseconds integer
) SECURITY DEFINER;
ALTER function net.http_post(
    url text,
    body jsonb,
    params jsonb,
    headers jsonb,
    timeout_milliseconds integer
) SECURITY DEFINER;
ALTER function net.http_get(
    url text,
    params jsonb,
    headers jsonb,
    timeout_milliseconds integer
)
SET search_path = net;
ALTER function net.http_post(
    url text,
    body jsonb,
    params jsonb,
    headers jsonb,
    timeout_milliseconds integer
)
SET search_path = net;
REVOKE ALL ON FUNCTION net.http_get(
    url text,
    params jsonb,
    headers jsonb,
    timeout_milliseconds integer
)
FROM PUBLIC;
REVOKE ALL ON FUNCTION net.http_post(
    url text,
    body jsonb,
    params jsonb,
    headers jsonb,
    timeout_milliseconds integer
)
FROM PUBLIC;
GRANT EXECUTE ON FUNCTION net.http_get(
        url text,
        params jsonb,
        headers jsonb,
        timeout_milliseconds integer
    ) TO supabase_functions_admin,
    postgres,
    anon,
    authenticated,
    service_role;
GRANT EXECUTE ON FUNCTION net.http_post(
        url text,
        body jsonb,
        params jsonb,
        headers jsonb,
        timeout_milliseconds integer
    ) TO supabase_functions_admin,
    postgres,
    anon,
    authenticated,
    service_role;
END IF;
END;
$$;
ALTER FUNCTION "extensions"."grant_pg_net_access"() OWNER TO "supabase_admin";
COMMENT ON FUNCTION "extensions"."grant_pg_net_access"() IS 'Grants access to pg_net';
CREATE OR REPLACE FUNCTION "extensions"."pgrst_ddl_watch"() RETURNS "event_trigger" LANGUAGE "plpgsql" AS $$
DECLARE cmd record;
BEGIN FOR cmd IN
SELECT *
FROM pg_event_trigger_ddl_commands() LOOP IF cmd.command_tag IN (
        'CREATE SCHEMA',
        'ALTER SCHEMA',
        'CREATE TABLE',
        'CREATE TABLE AS',
        'SELECT INTO',
        'ALTER TABLE',
        'CREATE FOREIGN TABLE',
        'ALTER FOREIGN TABLE',
        'CREATE VIEW',
        'ALTER VIEW',
        'CREATE MATERIALIZED VIEW',
        'ALTER MATERIALIZED VIEW',
        'CREATE FUNCTION',
        'ALTER FUNCTION',
        'CREATE TRIGGER',
        'CREATE TYPE',
        'ALTER TYPE',
        'CREATE RULE',
        'COMMENT'
    ) -- don't notify in case of CREATE TEMP table or other objects created on pg_temp
    AND cmd.schema_name is distinct
from 'pg_temp' THEN NOTIFY pgrst,
    'reload schema';
END IF;
END LOOP;
END;
$$;
ALTER FUNCTION "extensions"."pgrst_ddl_watch"() OWNER TO "supabase_admin";
CREATE OR REPLACE FUNCTION "extensions"."pgrst_drop_watch"() RETURNS "event_trigger" LANGUAGE "plpgsql" AS $$
DECLARE obj record;
BEGIN FOR obj IN
SELECT *
FROM pg_event_trigger_dropped_objects() LOOP IF obj.object_type IN (
        'schema',
        'table',
        'foreign table',
        'view',
        'materialized view',
        'function',
        'trigger',
        'type',
        'rule'
    )
    AND obj.is_temporary IS false -- no pg_temp objects
    THEN NOTIFY pgrst,
    'reload schema';
END IF;
END LOOP;
END;
$$;
ALTER FUNCTION "extensions"."pgrst_drop_watch"() OWNER TO "supabase_admin";
CREATE OR REPLACE FUNCTION "extensions"."set_graphql_placeholder"() RETURNS "event_trigger" LANGUAGE "plpgsql" AS $_$
DECLARE graphql_is_dropped bool;
BEGIN graphql_is_dropped = (
    SELECT ev.schema_name = 'graphql_public'
    FROM pg_event_trigger_dropped_objects() AS ev
    WHERE ev.schema_name = 'graphql_public'
);
IF graphql_is_dropped THEN
create or replace function graphql_public.graphql(
        "operationName" text default null,
        query text default null,
        variables jsonb default null,
        extensions jsonb default null
    ) returns jsonb language plpgsql as $$
DECLARE server_version float;
BEGIN server_version = (
    SELECT (
            SPLIT_PART(
                (
                    select version()
                ),
                ' ',
                2
            )
        )::float
);
IF server_version >= 14 THEN RETURN jsonb_build_object(
    'errors',
    jsonb_build_array(
        jsonb_build_object(
            'message',
            'pg_graphql extension is not enabled.'
        )
    )
);
ELSE RETURN jsonb_build_object(
    'errors',
    jsonb_build_array(
        jsonb_build_object(
            'message',
            'pg_graphql is only available on projects running Postgres 14 onwards.'
        )
    )
);
END IF;
END;
$$;
END IF;
END;
$_$;
ALTER FUNCTION "extensions"."set_graphql_placeholder"() OWNER TO "supabase_admin";
COMMENT ON FUNCTION "extensions"."set_graphql_placeholder"() IS 'Reintroduces placeholder function for graphql_public.graphql';
CREATE OR REPLACE FUNCTION "public"."generate_monthly_invoice"("p_account_id" "uuid", "p_target_month" "date") RETURNS json LANGUAGE "plpgsql" AS $_$
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
FROM public.accounts
WHERE id = p_account_id;
IF v_account_timezone IS NULL THEN RAISE EXCEPTION '계정을 찾을 수 없습니다. (Account ID: %)',
p_account_id;
END IF;
v_start_time := date_trunc('month', p_target_month::timestamp) AT TIME ZONE v_account_timezone;
v_end_time := v_start_time + interval '1 month';
SELECT id INTO v_existing_invoice
FROM public.invoices
WHERE account_id = p_account_id
    AND billing_period_start = v_start_time;
IF v_existing_invoice IS NOT NULL THEN RAISE EXCEPTION '해당 월의 청구서가 이미 존재합니다. (Invoice ID: %)',
v_existing_invoice;
END IF;
SELECT COUNT(DISTINCT rate_card_id),
    (ARRAY_AGG(DISTINCT rate_card_id)) [1] INTO v_rate_card_count,
    v_rate_card_id
FROM public.subscriptions
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
    FROM public.usage_events ue
        JOIN public.price_dimensions pd ON pd.dimension_key = 'endpoint'
        AND pd.dimension_value = ue.properties->>'endpoint'
        JOIN public.prices p ON p.id = pd.price_id
        AND p.rate_card_id = v_rate_card_id
        AND ue.timestamp >= p.effective_start
        AND (
            p.effective_end IS NULL
            OR ue.timestamp < p.effective_end
        )
        JOIN public.billable_metrics bm ON bm.id = p.metric_id
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
    FROM public.usage_events ue
        JOIN public.price_dimensions pd ON pd.dimension_key = 'endpoint'
        AND pd.dimension_value = '*'
        JOIN public.prices p ON p.id = pd.price_id
        AND p.rate_card_id = v_rate_card_id
        AND ue.timestamp >= p.effective_start
        AND (
            p.effective_end IS NULL
            OR ue.timestamp < p.effective_end
        )
        JOIN public.billable_metrics bm ON bm.id = p.metric_id
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
        JOIN public.price_tiers pt ON pt.price_id = au.price_id
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
SELECT id INTO v_existing_invoice
FROM public.invoices
WHERE account_id = p_account_id
    AND billing_period_start = v_start_time;
RAISE EXCEPTION '해당 월의 청구서가 이미 존재합니다. (Invoice ID: %)',
v_existing_invoice;
END;
INSERT INTO public.invoice_line_items (
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
FROM public.credit_ledgers
WHERE account_id = p_account_id
ORDER BY created_at DESC,
    id DESC
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
$_$;
ALTER FUNCTION "public"."generate_monthly_invoice"("p_account_id" "uuid", "p_target_month" "date") OWNER TO "postgres";
SET default_tablespace = '';
SET default_table_access_method = "heap";
CREATE TABLE IF NOT EXISTS "public"."accounts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "parent_account_id" "uuid",
    "name" "text" NOT NULL,
    "timezone" "text" DEFAULT 'UTC'::"text" NOT NULL,
    "status" "text" NOT NULL,
    CONSTRAINT "accounts_parent_check" CHECK (
        (
            ("parent_account_id" IS NULL)
            OR ("parent_account_id" <> "id")
        )
    ),
    CONSTRAINT "accounts_status_check" CHECK (
        (
            "status" = ANY (
                ARRAY ['Active'::"text", 'Inactive'::"text", 'Suspended'::"text", 'Archived'::"text"]
            )
        )
    )
);
ALTER TABLE "public"."accounts" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."billable_metrics" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "event_name" "text" NOT NULL,
    "property_key" "text",
    "aggregation_type" "text" NOT NULL,
    "group_keys" "text" [],
    "sql_definition" "text"
);
ALTER TABLE "public"."billable_metrics" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."credit_ledgers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "account_id" "uuid" NOT NULL,
    "transaction_type" "text" NOT NULL,
    "amount" numeric(18, 2) DEFAULT 0 NOT NULL,
    "running_balance" numeric(18, 2) DEFAULT 0 NOT NULL,
    "reference_id" "text",
    "reference_type" character varying(50) NOT NULL,
    "currency" character varying(3) DEFAULT 'KRW'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "credit_ledgers_amount_check" CHECK (("amount" >= (0)::numeric)),
    CONSTRAINT "credit_ledgers_currency_check" CHECK ((("currency")::"text" ~ '^[A-Z]{3}$'::"text"))
);
ALTER TABLE "public"."credit_ledgers" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."invoice_line_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "invoice_id" "uuid" NOT NULL,
    "metric_id" "uuid" NOT NULL,
    "quantity" numeric DEFAULT 0 NOT NULL,
    "amount" numeric(18, 2) DEFAULT 0 NOT NULL,
    CONSTRAINT "line_item_amount_check" CHECK (
        (
            ("amount" >= (0)::numeric)
            AND ("quantity" >= (0)::numeric)
        )
    )
);
ALTER TABLE "public"."invoice_line_items" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."invoices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "account_id" "uuid" NOT NULL,
    "subtotal" numeric(18, 2) DEFAULT 0 NOT NULL,
    "total_amount" numeric(18, 2) DEFAULT 0 NOT NULL,
    "status" "text" NOT NULL,
    "billing_period_start" timestamp with time zone,
    "billing_period_end" timestamp with time zone,
    CONSTRAINT "invoice_amount_check" CHECK (
        (
            ("subtotal" >= (0)::numeric)
            AND ("total_amount" >= (0)::numeric)
        )
    ),
    CONSTRAINT "invoices_status_check" CHECK (
        (
            "status" = ANY (
                ARRAY ['Draft'::"text", 'Open'::"text", 'Paid'::"text", 'Void'::"text", 'Uncollectible'::"text"]
            )
        )
    )
);
ALTER TABLE "public"."invoices" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."price_dimensions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "price_id" "uuid" NOT NULL,
    "dimension_key" "text" NOT NULL,
    "dimension_value" "text" NOT NULL
);
ALTER TABLE "public"."price_dimensions" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."price_tiers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "price_id" "uuid" NOT NULL,
    "first_unit" numeric DEFAULT 0 NOT NULL,
    "last_unit" numeric,
    "unit_amount" numeric(18, 2) DEFAULT 0 NOT NULL,
    "flat_amount" numeric(18, 2) DEFAULT 0 NOT NULL,
    CONSTRAINT "tiers_unit_check" CHECK (
        (
            ("first_unit" >= (0)::numeric)
            AND ("unit_amount" >= (0)::numeric)
            AND ("flat_amount" >= (0)::numeric)
            AND (
                ("last_unit" IS NULL)
                OR ("first_unit" <= "last_unit")
            )
        )
    )
);
ALTER TABLE "public"."price_tiers" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."prices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rate_card_id" "uuid" NOT NULL,
    "metric_id" "uuid" NOT NULL,
    "pricing_model" "text" NOT NULL,
    "effective_start" timestamp with time zone NOT NULL,
    "effective_end" timestamp with time zone,
    CONSTRAINT "prices_date_check" CHECK (
        (
            ("effective_end" IS NULL)
            OR ("effective_start" < "effective_end")
        )
    )
);
ALTER TABLE "public"."prices" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."products" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL
);
ALTER TABLE "public"."products" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."rate_cards" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "product_id" "uuid" NOT NULL
);
ALTER TABLE "public"."rate_cards" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."subscriptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "account_id" "uuid" NOT NULL,
    "rate_card_id" "uuid" NOT NULL,
    "billing_interval" "text" NOT NULL,
    "current_period_start" timestamp with time zone NOT NULL,
    "current_period_end" timestamp with time zone NOT NULL,
    "status" "text" NOT NULL,
    CONSTRAINT "subs_status_check" CHECK (
        (
            "status" = ANY (
                ARRAY ['Active'::"text", 'Canceled'::"text", 'Past_Due'::"text", 'Trial'::"text"]
            )
        )
    )
);
ALTER TABLE "public"."subscriptions" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."usage_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "idempotency_key" "text" NOT NULL,
    "account_id" "uuid" NOT NULL,
    "event_name" "text" NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    "properties" "jsonb" DEFAULT '{}'::"jsonb",
    "ingested_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE "public"."usage_events" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."usage_events_archive" (
    "id" "uuid" NOT NULL,
    "idempotency_key" "text",
    "account_id" "uuid",
    "event_name" "text",
    "timestamp" timestamp with time zone,
    "properties" "jsonb",
    "ingested_at" timestamp with time zone
);
ALTER TABLE "public"."usage_events_archive" OWNER TO "postgres";
CREATE OR REPLACE VIEW "public"."v_dashboard_events" AS
SELECT "id",
    "account_id",
    "timestamp",
    ("properties"->>'endpoint'::"text") AS "endpoint",
    (("properties"->>'tokens_used'::"text"))::numeric AS "tokens_used",
    (("properties"->>'is_flagged_anomaly'::"text"))::boolean AS "is_flagged_anomaly"
FROM "public"."usage_events";
ALTER VIEW "public"."v_dashboard_events" OWNER TO "postgres";
CREATE OR REPLACE VIEW "public"."v_usage_anomalies" AS
SELECT "id",
    "account_id",
    "event_name",
    "timestamp",
    ("properties"->>'endpoint'::"text") AS "endpoint",
    ("properties"->>'region'::"text") AS "region",
    (("properties"->>'tokens_used'::"text"))::numeric AS "tokens_used",
    (
        (("properties"->>'tokens_used'::"text"))::numeric - (1000)::numeric
    ) AS "over_threshold_by",
    (("properties"->>'is_flagged_anomaly'::"text"))::boolean AS "is_flagged_anomaly",
    (("properties"->>'status_code'::"text"))::integer AS "status_code",
    "ingested_at"
FROM "public"."usage_events"
WHERE (
        ("properties" ? 'tokens_used'::"text")
        AND (
            ("properties"->>'tokens_used'::"text") ~ '^[0-9]+(\.[0-9]+)?$'::"text"
        )
        AND (
            (("properties"->>'tokens_used'::"text"))::numeric >= (1000)::numeric
        )
    );
ALTER VIEW "public"."v_usage_anomalies" OWNER TO "postgres";
ALTER TABLE ONLY "public"."accounts"
ADD CONSTRAINT "accounts_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."billable_metrics"
ADD CONSTRAINT "billable_metrics_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."credit_ledgers"
ADD CONSTRAINT "credit_ledgers_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."invoice_line_items"
ADD CONSTRAINT "invoice_line_items_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."invoices"
ADD CONSTRAINT "invoices_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."price_dimensions"
ADD CONSTRAINT "price_dimensions_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."price_tiers"
ADD CONSTRAINT "price_tiers_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."prices"
ADD CONSTRAINT "prices_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."products"
ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."rate_cards"
ADD CONSTRAINT "rate_cards_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."subscriptions"
ADD CONSTRAINT "subscriptions_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."price_tiers"
ADD CONSTRAINT "tiers_unique_start" UNIQUE ("price_id", "first_unit");
ALTER TABLE ONLY "public"."usage_events_archive"
ADD CONSTRAINT "usage_events_archive_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."usage_events"
ADD CONSTRAINT "usage_events_idempotency_key_key" UNIQUE ("idempotency_key");
ALTER TABLE ONLY "public"."usage_events"
ADD CONSTRAINT "usage_events_pkey" PRIMARY KEY ("id");
CREATE UNIQUE INDEX "invoices_account_billing_period_key" ON "public"."invoices" USING "btree" ("account_id", "billing_period_start")
WHERE ("billing_period_start" IS NOT NULL);
ALTER TABLE ONLY "public"."accounts"
ADD CONSTRAINT "accounts_parent_account_id_fkey" FOREIGN KEY ("parent_account_id") REFERENCES "public"."accounts"("id") ON DELETE
SET NULL;
ALTER TABLE ONLY "public"."credit_ledgers"
ADD CONSTRAINT "credit_ledgers_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE RESTRICT;
ALTER TABLE ONLY "public"."invoice_line_items"
ADD CONSTRAINT "invoice_line_items_invoice_id_fkey" FOREIGN KEY ("invoice_id") REFERENCES "public"."invoices"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."invoice_line_items"
ADD CONSTRAINT "invoice_line_items_metric_id_fkey" FOREIGN KEY ("metric_id") REFERENCES "public"."billable_metrics"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."invoices"
ADD CONSTRAINT "invoices_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE RESTRICT;
ALTER TABLE ONLY "public"."price_dimensions"
ADD CONSTRAINT "price_dimensions_price_id_fkey" FOREIGN KEY ("price_id") REFERENCES "public"."prices"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."price_tiers"
ADD CONSTRAINT "price_tiers_price_id_fkey" FOREIGN KEY ("price_id") REFERENCES "public"."prices"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."prices"
ADD CONSTRAINT "prices_metric_id_fkey" FOREIGN KEY ("metric_id") REFERENCES "public"."billable_metrics"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."prices"
ADD CONSTRAINT "prices_rate_card_id_fkey" FOREIGN KEY ("rate_card_id") REFERENCES "public"."rate_cards"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."rate_cards"
ADD CONSTRAINT "rate_cards_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."subscriptions"
ADD CONSTRAINT "subscriptions_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE RESTRICT;
ALTER TABLE ONLY "public"."subscriptions"
ADD CONSTRAINT "subscriptions_rate_card_id_fkey" FOREIGN KEY ("rate_card_id") REFERENCES "public"."rate_cards"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."usage_events"
ADD CONSTRAINT "usage_events_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE RESTRICT;
CREATE POLICY "Enable read access for all users" ON "public"."products" FOR
SELECT USING (true);
ALTER TABLE "public"."products" ENABLE ROW LEVEL SECURITY;
GRANT USAGE ON SCHEMA "extensions" TO "anon";
GRANT USAGE ON SCHEMA "extensions" TO "authenticated";
GRANT USAGE ON SCHEMA "extensions" TO "service_role";
GRANT ALL ON SCHEMA "extensions" TO "dashboard_user";
GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";
GRANT USAGE ON SCHEMA "vault" TO "postgres" WITH
GRANT OPTION;
GRANT USAGE ON SCHEMA "vault" TO "service_role";
REVOKE ALL ON FUNCTION "extensions"."grant_pg_cron_access"()
FROM "supabase_admin";
GRANT ALL ON FUNCTION "extensions"."grant_pg_cron_access"() TO "supabase_admin" WITH
GRANT OPTION;
GRANT ALL ON FUNCTION "extensions"."grant_pg_cron_access"() TO "dashboard_user";
GRANT ALL ON FUNCTION "extensions"."grant_pg_graphql_access"() TO "postgres" WITH
GRANT OPTION;
REVOKE ALL ON FUNCTION "extensions"."grant_pg_net_access"()
FROM "supabase_admin";
GRANT ALL ON FUNCTION "extensions"."grant_pg_net_access"() TO "supabase_admin" WITH
GRANT OPTION;
GRANT ALL ON FUNCTION "extensions"."grant_pg_net_access"() TO "dashboard_user";
GRANT ALL ON FUNCTION "extensions"."pgrst_ddl_watch"() TO "postgres" WITH
GRANT OPTION;
GRANT ALL ON FUNCTION "extensions"."pgrst_drop_watch"() TO "postgres" WITH
GRANT OPTION;
GRANT ALL ON FUNCTION "extensions"."set_graphql_placeholder"() TO "postgres" WITH
GRANT OPTION;
GRANT ALL ON FUNCTION "public"."generate_monthly_invoice"("p_account_id" "uuid", "p_target_month" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."generate_monthly_invoice"("p_account_id" "uuid", "p_target_month" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_monthly_invoice"("p_account_id" "uuid", "p_target_month" "date") TO "service_role";
GRANT ALL ON TABLE "public"."accounts" TO "anon";
GRANT ALL ON TABLE "public"."accounts" TO "authenticated";
GRANT ALL ON TABLE "public"."accounts" TO "service_role";
GRANT ALL ON TABLE "public"."billable_metrics" TO "anon";
GRANT ALL ON TABLE "public"."billable_metrics" TO "authenticated";
GRANT ALL ON TABLE "public"."billable_metrics" TO "service_role";
GRANT ALL ON TABLE "public"."credit_ledgers" TO "anon";
GRANT ALL ON TABLE "public"."credit_ledgers" TO "authenticated";
GRANT ALL ON TABLE "public"."credit_ledgers" TO "service_role";
GRANT ALL ON TABLE "public"."invoice_line_items" TO "anon";
GRANT ALL ON TABLE "public"."invoice_line_items" TO "authenticated";
GRANT ALL ON TABLE "public"."invoice_line_items" TO "service_role";
GRANT ALL ON TABLE "public"."invoices" TO "anon";
GRANT ALL ON TABLE "public"."invoices" TO "authenticated";
GRANT ALL ON TABLE "public"."invoices" TO "service_role";
GRANT ALL ON TABLE "public"."price_dimensions" TO "anon";
GRANT ALL ON TABLE "public"."price_dimensions" TO "authenticated";
GRANT ALL ON TABLE "public"."price_dimensions" TO "service_role";
GRANT ALL ON TABLE "public"."price_tiers" TO "anon";
GRANT ALL ON TABLE "public"."price_tiers" TO "authenticated";
GRANT ALL ON TABLE "public"."price_tiers" TO "service_role";
GRANT ALL ON TABLE "public"."prices" TO "anon";
GRANT ALL ON TABLE "public"."prices" TO "authenticated";
GRANT ALL ON TABLE "public"."prices" TO "service_role";
GRANT ALL ON TABLE "public"."products" TO "anon";
GRANT ALL ON TABLE "public"."products" TO "authenticated";
GRANT ALL ON TABLE "public"."products" TO "service_role";
GRANT ALL ON TABLE "public"."rate_cards" TO "anon";
GRANT ALL ON TABLE "public"."rate_cards" TO "authenticated";
GRANT ALL ON TABLE "public"."rate_cards" TO "service_role";
GRANT ALL ON TABLE "public"."subscriptions" TO "anon";
GRANT ALL ON TABLE "public"."subscriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."subscriptions" TO "service_role";
GRANT ALL ON TABLE "public"."usage_events" TO "anon";
GRANT ALL ON TABLE "public"."usage_events" TO "authenticated";
GRANT ALL ON TABLE "public"."usage_events" TO "service_role";
GRANT ALL ON TABLE "public"."usage_events_archive" TO "anon";
GRANT ALL ON TABLE "public"."usage_events_archive" TO "authenticated";
GRANT ALL ON TABLE "public"."usage_events_archive" TO "service_role";
GRANT ALL ON TABLE "public"."v_dashboard_events" TO "anon";
GRANT ALL ON TABLE "public"."v_dashboard_events" TO "authenticated";
GRANT ALL ON TABLE "public"."v_dashboard_events" TO "service_role";
GRANT ALL ON TABLE "public"."v_usage_anomalies" TO "anon";
GRANT ALL ON TABLE "public"."v_usage_anomalies" TO "authenticated";
GRANT ALL ON TABLE "public"."v_usage_anomalies" TO "service_role";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON SEQUENCES TO "service_role";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON FUNCTIONS TO "service_role";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON TABLES TO "service_role";
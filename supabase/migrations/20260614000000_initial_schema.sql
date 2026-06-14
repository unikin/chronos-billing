


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


CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "extensions";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";





SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."accounts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "parent_account_id" "uuid",
    "name" "text" NOT NULL,
    "timezone" "text" DEFAULT 'UTC'::"text" NOT NULL,
    "status" "text" NOT NULL,
    CONSTRAINT "accounts_parent_check" CHECK ((("parent_account_id" IS NULL) OR ("parent_account_id" <> "id"))),
    CONSTRAINT "accounts_status_check" CHECK (("status" = ANY (ARRAY['Active'::"text", 'Inactive'::"text", 'Suspended'::"text", 'Archived'::"text"])))
);


ALTER TABLE "public"."accounts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."billable_metrics" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "event_name" "text" NOT NULL,
    "property_key" "text",
    "aggregation_type" "text" NOT NULL,
    "group_keys" "text"[],
    "sql_definition" "text"
);


ALTER TABLE "public"."billable_metrics" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."credit_ledgers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "account_id" "uuid" NOT NULL,
    "transaction_type" "text" NOT NULL,
    "amount" numeric(18,2) DEFAULT 0 NOT NULL,
    "running_balance" numeric(18,2) DEFAULT 0 NOT NULL,
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
    "amount" numeric(18,2) DEFAULT 0 NOT NULL,
    CONSTRAINT "line_item_amount_check" CHECK ((("amount" >= (0)::numeric) AND ("quantity" >= (0)::numeric)))
);


ALTER TABLE "public"."invoice_line_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."invoices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "account_id" "uuid" NOT NULL,
    "subtotal" numeric(18,2) DEFAULT 0 NOT NULL,
    "total_amount" numeric(18,2) DEFAULT 0 NOT NULL,
    "status" "text" NOT NULL,
    CONSTRAINT "invoice_amount_check" CHECK ((("subtotal" >= (0)::numeric) AND ("total_amount" >= (0)::numeric))),
    CONSTRAINT "invoices_status_check" CHECK (("status" = ANY (ARRAY['Draft'::"text", 'Open'::"text", 'Paid'::"text", 'Void'::"text", 'Uncollectible'::"text"])))
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
    "unit_amount" numeric(18,2) DEFAULT 0 NOT NULL,
    "flat_amount" numeric(18,2) DEFAULT 0 NOT NULL,
    CONSTRAINT "tiers_unit_check" CHECK ((("first_unit" >= (0)::numeric) AND ("unit_amount" >= (0)::numeric) AND ("flat_amount" >= (0)::numeric) AND (("last_unit" IS NULL) OR ("first_unit" <= "last_unit"))))
);


ALTER TABLE "public"."price_tiers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."prices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rate_card_id" "uuid" NOT NULL,
    "metric_id" "uuid" NOT NULL,
    "pricing_model" "text" NOT NULL,
    "effective_start" timestamp with time zone NOT NULL,
    "effective_end" timestamp with time zone,
    CONSTRAINT "prices_date_check" CHECK ((("effective_end" IS NULL) OR ("effective_start" < "effective_end")))
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
    CONSTRAINT "subs_status_check" CHECK (("status" = ANY (ARRAY['Active'::"text", 'Canceled'::"text", 'Past_Due'::"text", 'Trial'::"text"])))
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
    ("properties" ->> 'endpoint'::"text") AS "endpoint",
    (("properties" ->> 'tokens_used'::"text"))::numeric AS "tokens_used",
    (("properties" ->> 'is_flagged_anomaly'::"text"))::boolean AS "is_flagged_anomaly"
   FROM "public"."usage_events";


ALTER VIEW "public"."v_dashboard_events" OWNER TO "postgres";


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



ALTER TABLE ONLY "public"."accounts"
    ADD CONSTRAINT "accounts_parent_account_id_fkey" FOREIGN KEY ("parent_account_id") REFERENCES "public"."accounts"("id") ON DELETE SET NULL;



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



CREATE POLICY "Enable read access for all users" ON "public"."products" FOR SELECT USING (true);



ALTER TABLE "public"."products" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";





GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";














































































































































































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









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";
































-- Backend-only Clover POS integration: pushes a newly-placed Farlo order into
-- a truck's Clover account (order + line items + a print trigger) via a
-- merchant-specific API token the owner generates themselves from their own
-- Clover dashboard — no Clover App Market listing/OAuth review needed for a
-- single-merchant integration. No Flutter app changes required at all.

CREATE TABLE IF NOT EXISTS "public"."pos_integrations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "truck_id" "uuid" NOT NULL,
    "provider" "text" DEFAULT 'clover'::"text" NOT NULL,
    "external_merchant_id" "text" NOT NULL,
    "api_token_secret_name" "text" NOT NULL,
    "clover_order_type_id" "text",
    "environment" "text" DEFAULT 'production'::"text" NOT NULL,
    "enabled" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "pos_integrations_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "pos_integrations_truck_id_fkey" FOREIGN KEY ("truck_id") REFERENCES "public"."food_trucks"("id") ON DELETE CASCADE,
    CONSTRAINT "pos_integrations_truck_id_provider_key" UNIQUE ("truck_id", "provider"),
    CONSTRAINT "pos_integrations_provider_check" CHECK (("provider" = ANY (ARRAY['clover'::"text"]))),
    CONSTRAINT "pos_integrations_environment_check" CHECK (("environment" = ANY (ARRAY['production'::"text", 'sandbox'::"text"])))
);

ALTER TABLE "public"."pos_integrations" OWNER TO "postgres";
ALTER TABLE "public"."pos_integrations" ENABLE ROW LEVEL SECURITY;
-- No policies for anon/authenticated — this holds credential references and
-- has no owner-facing UI yet; only service_role (the edge function) and
-- direct SQL access (manual onboarding) touch it.
GRANT ALL ON TABLE "public"."pos_integrations" TO "service_role";

CREATE TABLE IF NOT EXISTS "public"."pos_push_attempts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "truck_id" "uuid" NOT NULL,
    "provider" "text" NOT NULL,
    "success" boolean NOT NULL,
    "error" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "pos_push_attempts_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "pos_push_attempts_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE,
    CONSTRAINT "pos_push_attempts_truck_id_fkey" FOREIGN KEY ("truck_id") REFERENCES "public"."food_trucks"("id") ON DELETE CASCADE
);

ALTER TABLE "public"."pos_push_attempts" OWNER TO "postgres";
ALTER TABLE "public"."pos_push_attempts" ENABLE ROW LEVEL SECURITY;
GRANT ALL ON TABLE "public"."pos_push_attempts" TO "service_role";

-- Narrow lookup used only by the push-order-to-clover edge function
-- (service_role) to resolve a truck's Clover credentials, decrypting the
-- Vault-stored API token in the same call.
CREATE OR REPLACE FUNCTION "public"."get_clover_credentials"("p_truck_id" "uuid")
RETURNS TABLE("external_merchant_id" "text", "api_token" "text", "clover_order_type_id" "text", "environment" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT pi.external_merchant_id, vs.decrypted_secret, pi.clover_order_type_id, pi.environment
  FROM pos_integrations pi
  JOIN vault.decrypted_secrets vs ON vs.name = pi.api_token_secret_name
  WHERE pi.truck_id = p_truck_id AND pi.provider = 'clover' AND pi.enabled = true;
$$;

ALTER FUNCTION "public"."get_clover_credentials"("p_truck_id" "uuid") OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."get_clover_credentials"("p_truck_id" "uuid") FROM PUBLIC;
REVOKE ALL ON FUNCTION "public"."get_clover_credentials"("p_truck_id" "uuid") FROM "anon";
REVOKE ALL ON FUNCTION "public"."get_clover_credentials"("p_truck_id" "uuid") FROM "authenticated";
GRANT EXECUTE ON FUNCTION "public"."get_clover_credentials"("p_truck_id" "uuid") TO "service_role";

-- Fired on every order INSERT. Cheap EXISTS check means this is a no-op for
-- every truck without Clover configured. Reuses the existing agent_cron_bearer
-- Vault secret / AGENT_EMAIL_SECRET edge-function env var (already live,
-- already used by agent_cron_call/founder_trigger_agent to call agent-sage
-- etc.) as the shared auth secret for this trigger -> edge function call —
-- no new secret needed anywhere. net.http_post is async, so a slow/down
-- Clover never blocks or delays the actual order placement.
CREATE OR REPLACE FUNCTION "public"."push_order_to_clover"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_has_integration boolean;
  v_bearer text;
begin
  select exists(
    select 1 from pos_integrations
    where truck_id = new.truck_id and provider = 'clover' and enabled = true
  ) into v_has_integration;

  if not v_has_integration then
    return new;
  end if;

  select decrypted_secret into v_bearer from vault.decrypted_secrets where name = 'agent_cron_bearer';

  perform net.http_post(
    url := 'https://weflrxyerxpsafcdetya.supabase.co/functions/v1/push-order-to-clover',
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_bearer, 'Content-Type', 'application/json'),
    body := jsonb_build_object('order_id', new.id)
  );

  return new;
end;
$$;

ALTER FUNCTION "public"."push_order_to_clover"() OWNER TO "postgres";

CREATE TRIGGER "push_order_to_clover_trigger" AFTER INSERT ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."push_order_to_clover"();

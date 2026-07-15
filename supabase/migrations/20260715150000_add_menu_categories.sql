-- Category order was previously implicit: whichever category's first menu_item
-- happened to have the lowest sort_order (a single global counter shared by
-- every item across every category) determined display order, with no way for
-- an owner to change it after the fact. This table gives category order its
-- own explicit, independently-editable value.
CREATE TABLE IF NOT EXISTS "public"."menu_categories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "truck_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "menu_categories_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "menu_categories_truck_id_fkey" FOREIGN KEY ("truck_id") REFERENCES "public"."food_trucks"("id") ON DELETE CASCADE,
    CONSTRAINT "menu_categories_truck_id_name_key" UNIQUE ("truck_id", "name")
);

ALTER TABLE "public"."menu_categories" OWNER TO "postgres";

CREATE INDEX "idx_menu_categories_truck" ON "public"."menu_categories" USING "btree" ("truck_id", "sort_order");

ALTER TABLE "public"."menu_categories" ENABLE ROW LEVEL SECURITY;

-- Same shape as menu_items' RLS: public read, owner-only write.
CREATE POLICY "menu_categories_read" ON "public"."menu_categories" FOR SELECT USING (true);

CREATE POLICY "menu_categories_insert" ON "public"."menu_categories" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."food_trucks"
  WHERE (("food_trucks"."id" = "menu_categories"."truck_id") AND ("food_trucks"."owner_id" = "auth"."uid"())))));

CREATE POLICY "menu_categories_update" ON "public"."menu_categories" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."food_trucks"
  WHERE (("food_trucks"."id" = "menu_categories"."truck_id") AND ("food_trucks"."owner_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."food_trucks"
  WHERE (("food_trucks"."id" = "menu_categories"."truck_id") AND ("food_trucks"."owner_id" = "auth"."uid"())))));

CREATE POLICY "menu_categories_delete" ON "public"."menu_categories" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."food_trucks"
  WHERE (("food_trucks"."id" = "menu_categories"."truck_id") AND ("food_trucks"."owner_id" = "auth"."uid"())))));

GRANT ALL ON TABLE "public"."menu_categories" TO "anon";
GRANT ALL ON TABLE "public"."menu_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."menu_categories" TO "service_role";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."menu_categories";

-- Backfill: preserve today's implicit order (by each category's earliest
-- menu_item sort_order) as the explicit starting sort_order, for every
-- (truck_id, category) pair that already exists.
INSERT INTO "public"."menu_categories" ("truck_id", "name", "sort_order")
SELECT
  "truck_id",
  "category",
  (ROW_NUMBER() OVER (PARTITION BY "truck_id" ORDER BY MIN("sort_order"), MIN("created_at")) - 1) AS "sort_order"
FROM "public"."menu_items"
GROUP BY "truck_id", "category"
ON CONFLICT ("truck_id", "name") DO NOTHING;

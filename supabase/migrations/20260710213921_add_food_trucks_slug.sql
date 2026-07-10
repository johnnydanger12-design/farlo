-- Adds a stable, human-readable slug per business for the new public
-- visit.farlo.app share page. Generated server-side on INSERT so every
-- future signup gets one automatically, with zero Flutter/app-release
-- dependency. Never regenerated on a later name edit, so a distributed
-- share link never breaks.

ALTER TABLE public.food_trucks ADD COLUMN IF NOT EXISTS slug text UNIQUE;

CREATE OR REPLACE FUNCTION public.generate_food_truck_slug()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  base_slug text;
  candidate_slug text;
  suffix integer := 1;
BEGIN
  IF NEW.slug IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Drop apostrophes entirely (so "Cisco's" -> "ciscos", not "cisco-s"),
  -- then collapse any other run of non-alphanumeric characters into a
  -- single hyphen, then trim leading/trailing hyphens.
  base_slug := lower(NEW.name);
  base_slug := replace(base_slug, '''', '');
  base_slug := regexp_replace(base_slug, '[^a-z0-9]+', '-', 'g');
  base_slug := trim(both '-' from base_slug);

  IF base_slug = '' THEN
    base_slug := 'business';
  END IF;

  candidate_slug := base_slug;
  WHILE EXISTS (SELECT 1 FROM public.food_trucks WHERE slug = candidate_slug) LOOP
    suffix := suffix + 1;
    candidate_slug := base_slug || '-' || suffix;
  END LOOP;

  NEW.slug := candidate_slug;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_food_truck_slug ON public.food_trucks;
CREATE TRIGGER set_food_truck_slug
BEFORE INSERT ON public.food_trucks
FOR EACH ROW
EXECUTE FUNCTION public.generate_food_truck_slug();

-- Backfill existing rows using the exact same logic as the trigger, so
-- there's no chance of a hand-computed value drifting from what the
-- function would actually produce.
UPDATE public.food_trucks
SET slug = (
  SELECT trim(both '-' from regexp_replace(replace(lower(name), '''', ''), '[^a-z0-9]+', '-', 'g'))
)
WHERE slug IS NULL;

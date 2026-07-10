-- The first pass only stripped the ASCII apostrophe ('), but iOS/Android
-- keyboards auto-convert typed apostrophes to the Unicode curly right
-- single quote (' U+2019) -- confirmed live on Hope's own business name
-- ("Cisco's Grill and Grub"), which produced "cisco-s-grill-and-grub"
-- instead of the intended "ciscos-grill-and-grub". Strip both variants
-- (and the less common left single quote / backtick, for robustness).
--
-- NOTE: this attempt's character-class regex was itself buggy (see the
-- next migration) -- kept as-is here for an honest history rather than
-- rewritten after the fact.

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

  base_slug := lower(NEW.name);
  base_slug := regexp_replace(base_slug, '[''`]', '', 'g');
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

-- Re-backfill using the corrected logic.
UPDATE public.food_trucks
SET slug = (
  SELECT trim(both '-' from regexp_replace(regexp_replace(lower(name), '[''`]', '', 'g'), '[^a-z0-9]+', '-', 'g'))
);

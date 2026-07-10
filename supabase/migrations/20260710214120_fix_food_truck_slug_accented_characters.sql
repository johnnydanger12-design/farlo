-- Accented Latin characters (e, n-with-tilde, etc. -- common in real
-- business names, e.g. several Hartsville prospects like "Antojitos
-- Delia") were being destroyed rather than transliterated: "Jose's Cafe"
-- (with accents) produced "jos-s-caf" since [^a-z0-9] treats accented
-- letters as non-alphanumeric and hyphenates them away. unaccent() strips
-- diacritics first (accented e -> plain e) so the underlying letters
-- survive.

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA extensions;

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
  base_slug := replace(base_slug, '''', '');
  base_slug := replace(base_slug, chr(8217), '');
  base_slug := replace(base_slug, chr(8216), '');
  base_slug := replace(base_slug, '`', '');
  base_slug := extensions.unaccent(base_slug);
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

UPDATE public.food_trucks
SET slug = (
  SELECT trim(both '-' from regexp_replace(
    extensions.unaccent(replace(replace(replace(replace(lower(name), '''', ''), chr(8217), ''), chr(8216), ''), '`', '')),
    '[^a-z0-9]+', '-', 'g'
  ))
);

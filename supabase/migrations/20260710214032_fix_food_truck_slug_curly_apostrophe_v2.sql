-- Previous attempt's character-class regex silently failed to include the
-- actual curly-quote character (a literal-Unicode-in-SQL-string mistake).
-- Using chr() codes instead of pasting special characters directly removes
-- any ambiguity: chr(8217) = U+2019 (right single quote, curly), chr(8216) =
-- U+2018 (left single quote, curly).

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
    replace(replace(replace(replace(lower(name), '''', ''), chr(8217), ''), chr(8216), ''), '`', ''),
    '[^a-z0-9]+', '-', 'g'
  ))
);

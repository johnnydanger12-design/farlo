-- Fixes a real bug found live: Miles (agent-miles) correctly refused to draft outreach to
-- 5 SECOND WAVE prospects when the sales_targets directive explicitly says second wave
-- starts only after first wave has replies, and first wave hadn't even started yet. Root
-- cause: agent-miles's fetch of "uncontacted" prospects had no ORDER BY at all, so which 5
-- prospects got served was essentially arbitrary — sorting by created_at wouldn't have
-- fixed it either, since the two waves were inserted milliseconds apart in the same
-- Google Places prospecting batch. The "wave" concept only ever existed as free text in
-- the directive, which the fetch query never read. Adding a real column so wave ordering
-- is enforced by the database, not by the model correctly cross-referencing prose.
ALTER TABLE public.sales_prospects ADD COLUMN outreach_wave integer;

UPDATE public.sales_prospects SET outreach_wave = 1
WHERE business_name IN (
  'Emani''s Bakeology', 'Antojitos Delia', 'Cashua Coffee Roasters', 'Rise & Grind Coffee Cafe',
  'Crema Coffee Bar and Catering', 'Pour Friends Coffee Cream and Crumbs', 'Brooklyn Flames',
  'Taqueria Los Barcos', 'Jireh Soul Food Restaurant', 'Westwood BBQ', 'Mr. B''s Seafood',
  'Big Daddy''s Pizza & Wings', 'Block & Vino', 'Mighty Oak Market',
  'Maryland Fried Chicken / The Shrimper', 'Ruth''s Drive In', 'Carolina Lunch',
  'Pam''s Restaurant & Banquets', 'Jazzy Blues 843', 'Wild Heart Brewing Company',
  'Groucho''s Deli', 'Sam Kendall''s', 'The Boonies Bar & Grill', 'The Rooster One Thirty Six'
);

UPDATE public.sales_prospects SET outreach_wave = 2
WHERE business_name IN (
  'BBQ Soul', 'Wingz & Ale', 'J Michael''s Bar & Grill', 'The Rooftop at The Mantissa',
  'Black Creek Bistro', 'Cisco''s Grill and Grub', 'The Blind Pig Pub', 'Fuji Express',
  'Yogi Bear Honey Fried Chicken', 'Simply Sweet Cakes & more', 'sugaRush', 'Cakes By Jeanie',
  'Griggs Circle Bakery', 'CJ''s Cakes & Catering', 'Hidden Treasures', 'Tommy''s Self Services'
);

-- A few names in the directive were slightly off from what Google Places actually
-- returned (punctuation/suffix differences) — matched by hand after confirming via ILIKE
-- that these are the same businesses, not missing data.
UPDATE public.sales_prospects SET outreach_wave = 1
WHERE business_name IN (
  'Jireh | Soul Food Restaurant',
  'Pour Friends Coffee, Cream and Crumbs',
  'Maryland Fried Chicken of Hartsville / The Shrimper'
);

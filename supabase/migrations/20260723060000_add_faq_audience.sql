-- FAQ split: consumer vs. owner content. Per-question tagging rather than
-- per-category, since one existing question ("I have a consumer account —
-- how do I start my own business on Farlo?") is itself addressed to a
-- consumer despite living in the owner-facing "Getting Started" category.
alter table faq_items add column audience text not null default 'owner'
  check (audience in ('owner', 'consumer', 'both'));
update faq_items set audience = 'consumer'
  where question = 'I have a consumer account — how do I start my own business on Farlo?';

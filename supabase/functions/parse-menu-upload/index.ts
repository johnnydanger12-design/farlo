// Lets a truck owner upload a photo or PDF of their paper menu and have Claude
// parse it into structured menu items. This function only extracts and returns
// the parsed list — it never writes to menu_items/menu_categories itself. The
// owner reviews/edits the result client-side before anything is committed.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { encodeBase64 } from 'https://deno.land/std@0.224.0/encoding/base64.ts';

const ANTHROPIC_API_URL = 'https://api.anthropic.com/v1/messages';
const ANTHROPIC_VERSION = '2023-06-01';
const MODEL_SONNET = 'claude-sonnet-5';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

const SYSTEM_PROMPT = `You are extracting a food truck's menu from an uploaded photo or PDF of a paper menu into structured data. Call extract_menu_items exactly once with everything you can confidently read. Skip illegible or ambiguous items entirely — never guess a price or invent an item that isn't clearly there. A missing item is far better than a wrong one, since the owner reviews this list before anything is saved.`;

const EXTRACT_MENU_ITEMS_TOOL = {
  name: 'extract_menu_items',
  description:
    "Record every menu item you can confidently read from the attached photo or document of a food truck's paper menu. Only include an item if you can read its name and price with confidence. If a section, item, or price is blurry, cut off, obscured, or otherwise illegible, omit that item entirely rather than guessing.",
  input_schema: {
    type: 'object',
    properties: {
      items: {
        type: 'array',
        description: 'Menu items extracted from the source, in the order they appear on the menu.',
        items: {
          type: 'object',
          properties: {
            name: { type: 'string', description: "The item's name exactly as printed, cleaned of stray OCR artifacts." },
            description: {
              type: 'string',
              description: 'Any descriptive text under/beside the item name (ingredients, etc). Omit this field entirely if the menu has none for this item — do not invent one.',
            },
            price: {
              type: 'number',
              description: 'The item\'s price as a plain decimal number in dollars (e.g. 8.5 for "$8.50"). If an item lists multiple sizes/prices, use the first/base price.',
            },
            category: {
              type: 'string',
              description: "The section heading this item appears under on the menu (e.g. 'Tacos', 'Drinks', 'Sides'). If the menu has no visible section headings at all, use 'Mains' for every item rather than inventing arbitrary categories.",
            },
          },
          required: ['name', 'price', 'category'],
        },
      },
    },
    required: ['items'],
  },
};

function mediaTypeFor(blobType: string | undefined, storagePath: string): string {
  if (blobType) return blobType;
  const ext = storagePath.split('.').pop()?.toLowerCase();
  switch (ext) {
    case 'pdf': return 'application/pdf';
    case 'png': return 'image/png';
    case 'webp': return 'image/webp';
    default: return 'image/jpeg';
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return new Response('Unauthorized', { status: 401 });

  const apiKey = Deno.env.get('ANTHROPIC_API_KEY');
  if (!apiKey) {
    return new Response(JSON.stringify({ error: 'Claude not configured' }), {
      status: 500, headers: { 'Content-Type': 'application/json' },
    });
  }

  // Verify caller is authenticated
  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return new Response('Unauthorized', { status: 401 });

  let body: { truck_id: string; storage_path: string };
  try {
    body = await req.json();
  } catch {
    return new Response('Bad request', { status: 400 });
  }
  const { truck_id: truckId, storage_path: storagePath } = body;
  if (!truckId || !storagePath) {
    return new Response(
      JSON.stringify({ error: 'truck_id and storage_path are required' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    );
  }

  // Verify caller owns this truck
  const { data: truck } = await supabase
    .from('food_trucks')
    .select('owner_id')
    .eq('id', truckId)
    .single();

  if (!truck || truck.owner_id !== user.id) {
    return new Response('Forbidden', { status: 403 });
  }

  // Same subscription-lapse recheck as create-booking-payment-intent — each
  // parse is a real Claude API cost, gated the same way other paid-adjacent
  // owner actions already are.
  const { data: hasSub } = await supabase.rpc('owner_has_active_subscription', {
    p_owner_id: truck.owner_id,
  });
  if (!hasSub) {
    return new Response(
      JSON.stringify({ error: 'truck_subscription_inactive' }),
      { status: 422, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const { data: fileBlob, error: downloadError } = await supabase.storage
    .from('truck-menus')
    .download(storagePath);
  if (downloadError || !fileBlob) {
    return new Response(
      JSON.stringify({ error: 'Could not read the uploaded file' }),
      { status: 404, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const bytes = new Uint8Array(await fileBlob.arrayBuffer());
  const mediaType = mediaTypeFor(fileBlob.type, storagePath);
  const data = encodeBase64(bytes);

  // base64, not a signed URL — this codebase already found (aiden-chat) that
  // Claude's Messages API silently fails to resolve a source.type:'url' block.
  const contentBlock = mediaType === 'application/pdf'
    ? { type: 'document', source: { type: 'base64', media_type: mediaType, data } }
    : { type: 'image', source: { type: 'base64', media_type: mediaType, data } };

  try {
    // A single forced tool call, not runAgentLoop's multi-turn loop — that loop
    // resends the same tools/params every iteration with no "stop after the
    // first forced call" logic, so a forced tool_choice inside it would force
    // the same tool again on every subsequent turn until hitting its safety
    // valve. A one-shot direct call avoids that entirely.
    const res = await fetch(ANTHROPIC_API_URL, {
      method: 'POST',
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': ANTHROPIC_VERSION,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        model: MODEL_SONNET,
        max_tokens: 4096,
        system: SYSTEM_PROMPT,
        tools: [EXTRACT_MENU_ITEMS_TOOL],
        tool_choice: { type: 'tool', name: 'extract_menu_items' },
        messages: [{
          role: 'user',
          content: [
            { type: 'text', text: "Here is a photo/document of a food truck's menu. Extract every item you can confidently read." },
            contentBlock,
          ],
        }],
      }),
    });

    if (!res.ok) {
      const errText = await res.text();
      console.error('Anthropic API error:', errText);
      return new Response(
        JSON.stringify({ error: 'claude_parse_failed' }),
        { status: 502, headers: { 'Content-Type': 'application/json' } },
      );
    }

    // deno-lint-ignore no-explicit-any
    const responseData: any = await res.json();
    // deno-lint-ignore no-explicit-any
    const toolUse = (responseData.content ?? []).find((b: any) => b.type === 'tool_use');
    const items = toolUse?.input?.items ?? [];

    return new Response(
      JSON.stringify({ items }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('parse-menu-upload failed:', err);
    return new Response(
      JSON.stringify({ error: 'claude_parse_failed' }),
      { status: 502, headers: { 'Content-Type': 'application/json' } },
    );
  }
});

// Self-serve Clover connect: resolves the caller's own truck, re-validates
// credentials live (never trusts a client-reported "already tested" flag),
// best-effort creates a dedicated "Farlo Order" Clover employee purely so
// printed tickets show a server name (API-created orders otherwise print
// with no server name at all), stores the token in Vault, disables any other
// enabled pos_integrations row for this truck, and upserts the new row.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { cloverBaseUrl, testCloverConnection } from '../_shared/clover.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

// Best-effort. Only `name` is required by Clover's Employees API — deliberately
// omits `email` so this never triggers a real invite email to be sent (Clover
// only sends one when an email is present). No PIN/roles needed either since
// this "employee" is never actually logged into by a person, only referenced
// by id on API-created orders. Requires the token's Employees scope, which is
// separate from Orders/Print/Payments/Customers — a merchant who didn't select
// it when generating their token will simply get no employee id back here.
async function createFarloEmployee(
  merchantId: string,
  apiToken: string,
  environment: string,
): Promise<string | null> {
  try {
    const res = await fetch(`${cloverBaseUrl(environment)}/v3/merchants/${merchantId}/employees`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'Farlo Order' }),
    });
    if (!res.ok) {
      console.warn(`Clover employee create failed (${res.status}): ${await res.text()}`);
      return null;
    }
    const created = await res.json();
    return created?.id ?? null;
  } catch (err) {
    console.warn('createFarloEmployee failed:', err);
    return null;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return new Response('Unauthorized', { status: 401 });

  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return new Response('Unauthorized', { status: 401 });

  let body: { merchant_id?: string; api_token?: string; environment?: string; order_type_id?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'bad_request' }), { status: 400 });
  }
  const { merchant_id: merchantId, api_token: apiToken, environment, order_type_id: orderTypeId } = body;
  if (!merchantId || !apiToken || !environment) {
    return new Response(JSON.stringify({ error: 'merchant_id, api_token, and environment are required' }), { status: 400 });
  }

  // Resolves the caller's own truck — an employee (not the owner) attempting
  // to connect a POS gets rejected here rather than silently no-op'ing.
  const { data: truck, error: truckError } = await supabase
    .from('food_trucks')
    .select('id')
    .eq('owner_id', user.id)
    .single();
  if (truckError || !truck) {
    return new Response(JSON.stringify({ error: 'not_a_truck_owner' }), { status: 403 });
  }

  const testResult = await testCloverConnection(merchantId, apiToken, environment);
  if (!testResult.ok) {
    return new Response(JSON.stringify({ error: testResult.reason, message: testResult.message }), { status: 422 });
  }

  const employeeId = await createFarloEmployee(merchantId, apiToken, environment);

  const secretName = `clover_api_token_${truck.id}_${Date.now()}`;
  const { error: secretError } = await supabase.rpc('create_pos_secret', {
    p_secret: apiToken,
    p_name: secretName,
  });
  if (secretError) {
    console.error('create_pos_secret failed:', secretError);
    return new Response(JSON.stringify({ error: 'secret_store_failed' }), { status: 500 });
  }

  // Only one enabled POS integration per truck (enforced by
  // pos_integrations_truck_enabled_idx) — disable any other provider's row
  // before enabling this one.
  await supabase.from('pos_integrations').update({ enabled: false }).eq('truck_id', truck.id);

  const { error: upsertError } = await supabase
    .from('pos_integrations')
    .upsert(
      {
        truck_id: truck.id,
        provider: 'clover',
        external_merchant_id: merchantId,
        api_token_secret_name: secretName,
        clover_order_type_id: orderTypeId || null,
        clover_employee_id: employeeId,
        environment,
        enabled: true,
      },
      { onConflict: 'truck_id,provider' },
    );
  if (upsertError) {
    console.error('pos_integrations upsert failed:', upsertError);
    return new Response(JSON.stringify({ error: 'save_failed' }), { status: 500 });
  }

  return new Response(
    JSON.stringify({ success: true, employee_created: !!employeeId }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});

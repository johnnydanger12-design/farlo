import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function fmtDate(iso: string): string {
  const d = new Date(iso + 'T00:00:00'); // treat as local date, not UTC
  return d.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' });
}

function row(label: string, value: string | null | undefined): string {
  if (!value) return '';
  return `
    <tr>
      <td style="padding:6px 0;color:#6b7280;font-size:14px;width:140px;vertical-align:top">${label}</td>
      <td style="padding:6px 0;color:#111827;font-size:14px;vertical-align:top">${value}</td>
    </tr>`;
}

function buildHtml(params: {
  businessName: string;
  contactName: string;
  eventDate: string;
  eventTime: string;
  eventLocation: string;
  eventType: string;
  guestCount: number | null;
  duration: string | null;
  notes: string | null;
  contactEmail: string;
  contactPhone: string | null;
}): string {
  const {
    businessName, contactName, eventDate, eventTime, eventLocation,
    eventType, guestCount, duration, notes, contactEmail, contactPhone,
  } = params;

  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f9fafb;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#f9fafb;padding:32px 16px">
    <tr><td align="center">
      <table width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.08)">

        <!-- Header -->
        <tr>
          <td style="background:#111827;padding:28px 32px">
            <p style="margin:0;color:#ffffff;font-size:22px;font-weight:700">${businessName}</p>
            <p style="margin:6px 0 0;color:#9ca3af;font-size:14px">Booking Confirmation</p>
          </td>
        </tr>

        <!-- Body -->
        <tr>
          <td style="padding:32px">
            <p style="margin:0 0 8px;color:#111827;font-size:16px">Hi ${contactName},</p>
            <p style="margin:0 0 28px;color:#374151;font-size:15px;line-height:1.6">
              Your booking with <strong>${businessName}</strong> is confirmed. Here are the details:
            </p>

            <!-- Details table -->
            <table cellpadding="0" cellspacing="0" width="100%" style="border-top:1px solid #e5e7eb;border-bottom:1px solid #e5e7eb;margin-bottom:28px">
              <tbody>
                ${row('Date', fmtDate(eventDate))}
                ${row('Time', eventTime)}
                ${row('Location', eventLocation)}
                ${row('Event type', eventType)}
                ${row('Guests', guestCount != null ? String(guestCount) : null)}
                ${row('Duration', duration)}
                ${row('Your email', contactEmail)}
                ${row('Your phone', contactPhone)}
                ${notes ? row('Notes', notes) : ''}
              </tbody>
            </table>

            <p style="margin:0 0 28px;color:#374151;font-size:14px;line-height:1.6">
              If you have any questions about your booking, please reach out directly to <strong>${businessName}</strong>.
            </p>

            <p style="margin:0;color:#6b7280;font-size:13px">
              This confirmation was sent by Farlo on behalf of ${businessName}.
            </p>
          </td>
        </tr>

        <!-- Footer -->
        <tr>
          <td style="padding:20px 32px;border-top:1px solid #e5e7eb;background:#f9fafb">
            <p style="margin:0;color:#9ca3af;font-size:12px;text-align:center">
              Powered by <a href="https://farlo.app" style="color:#6b7280;text-decoration:none">Farlo</a>
            </p>
          </td>
        </tr>

      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  // Verify the caller has a valid Supabase session (the owner creating the booking).
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return new Response('Unauthorized', { status: 401 });

  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user }, error: authErr } = await userClient.auth.getUser();
  if (authErr || !user) return new Response('Unauthorized', { status: 401 });

  let body: { booking_id: string };
  try {
    body = await req.json();
  } catch {
    return new Response('Bad request', { status: 400 });
  }

  const { booking_id } = body;
  if (!booking_id) {
    return new Response(JSON.stringify({ error: 'booking_id required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Fetch the booking and the truck name in one round-trip.
  const { data: booking, error: bookingErr } = await supabase
    .from('event_booking_requests')
    .select('*, food_trucks(owner_id, name)')
    .eq('id', booking_id)
    .single();

  if (bookingErr || !booking) {
    return new Response(JSON.stringify({ error: 'booking_not_found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const truck = booking.food_trucks as Record<string, unknown>;

  // Only the truck owner can trigger this.
  if (truck?.owner_id !== user.id) return new Response('Forbidden', { status: 403 });

  const businessName = (truck.name as string) ?? 'Your vendor';
  const contactEmail = booking.contact_email as string;

  const { data: ownerData } = await supabase.auth.admin.getUserById(truck.owner_id as string);
  const ownerEmail = ownerData?.user?.email;

  if (!contactEmail) {
    return new Response(JSON.stringify({ error: 'no_contact_email' }), {
      status: 422,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const resendKey = Deno.env.get('RESEND_API_KEY');
  if (!resendKey) {
    console.warn('RESEND_API_KEY not set — skipping email');
    return new Response(JSON.stringify({ sent: false, reason: 'no_resend_key' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const html = buildHtml({
    businessName,
    contactName: booking.contact_name as string,
    eventDate: booking.event_date as string,
    eventTime: booking.event_time as string,
    eventLocation: booking.event_location as string,
    eventType: booking.event_type as string,
    guestCount: booking.guest_count as number | null,
    duration: booking.duration as string | null,
    notes: booking.notes as string | null,
    contactEmail,
    contactPhone: booking.contact_phone as string | null,
  });

  const emailRes = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${resendKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: 'Farlo Bookings <bookings@farlo.app>',
      to: [contactEmail],
      ...(ownerEmail ? { reply_to: [ownerEmail] } : {}),
      subject: `Booking Confirmed — ${businessName}`,
      html,
    }),
  });

  if (!emailRes.ok) {
    const err = await emailRes.text();
    console.error('Resend error:', err);
    return new Response(JSON.stringify({ sent: false, reason: 'resend_error' }), {
      status: 200, // fire-and-forget: don't surface email failures to the client
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify({ sent: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});

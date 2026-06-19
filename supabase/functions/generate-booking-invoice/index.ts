import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { PDFDocument, rgb, StandardFonts } from 'https://esm.sh/pdf-lib@1.17.1';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

// ─── Helpers ──────────────────────────────────────────────────────────────────

function fmtMoney(n: number): string {
  return `$${n.toFixed(2)}`;
}

function fmtDate(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
}

function invoiceNumber(bookingId: string): string {
  return bookingId.replace(/-/g, '').substring(0, 8).toUpperCase();
}

async function fetchLogoBytes(url: string): Promise<{ bytes: ArrayBuffer; isPng: boolean } | null> {
  try {
    const res = await fetch(url);
    if (!res.ok) return null;
    const ct = res.headers.get('content-type') ?? '';
    const isPng = ct.includes('png') || url.toLowerCase().includes('.png');
    return { bytes: await res.arrayBuffer(), isPng };
  } catch {
    return null;
  }
}

// ─── Handler ──────────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

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
  try { body = await req.json(); } catch { return new Response('Bad request', { status: 400 }); }

  const { booking_id } = body;
  if (!booking_id) return new Response(JSON.stringify({ error: 'booking_id required' }), { status: 400 });

  // Fetch booking + truck
  const { data: booking, error: bookingErr } = await supabase
    .from('event_booking_requests')
    .select('*, food_trucks(owner_id, name, logo_url, website_url, social_instagram, cuisine_type, cancellation_policy_hours)')
    .eq('id', booking_id)
    .single();

  if (bookingErr || !booking) return new Response(JSON.stringify({ error: 'booking_not_found' }), { status: 404 });

  const truck = booking.food_trucks as Record<string, unknown>;
  if (truck?.owner_id !== user.id) return new Response('Forbidden', { status: 403 });

  // Fetch quotes + deposit
  const { data: quotes } = await supabase
    .from('booking_quotes')
    .select('*')
    .eq('booking_id', booking_id)
    .order('created_at', { ascending: true });

  const { data: deposit } = await supabase
    .from('booking_deposits')
    .select('*')
    .eq('booking_id', booking_id)
    .maybeSingle();

  const estimate = (quotes ?? []).filter((q: Record<string, unknown>) => q.type === 'estimate').at(-1);
  const invoice = (quotes ?? []).filter((q: Record<string, unknown>) => q.type === 'invoice').at(-1);

  // ─── Build PDF ───────────────────────────────────────────────────────────────

  const pdfDoc = await PDFDocument.create();
  const page = pdfDoc.addPage([612, 792]); // US Letter
  const { width, height } = page.getSize();

  const fontBold = await pdfDoc.embedFont(StandardFonts.HelveticaBold);
  const fontReg = await pdfDoc.embedFont(StandardFonts.Helvetica);

  const black = rgb(0.08, 0.08, 0.08);
  const gray = rgb(0.5, 0.5, 0.5);
  const lightGray = rgb(0.92, 0.92, 0.92);
  const accent = rgb(0.15, 0.39, 0.92); // Farlo blue
  const green = rgb(0.1, 0.65, 0.35);

  const margin = 48;
  let y = height - margin;

  // ── Logo + business name (top-left) ─────────────────────────────────────────

  const logoUrl = truck.logo_url as string | null;
  let logoEndX = margin;

  if (logoUrl) {
    const logoData = await fetchLogoBytes(logoUrl);
    if (logoData) {
      try {
        const logoImg = logoData.isPng
          ? await pdfDoc.embedPng(logoData.bytes)
          : await pdfDoc.embedJpg(logoData.bytes);
        const scale = Math.min(48 / logoImg.height, 48 / logoImg.width);
        const lw = logoImg.width * scale;
        const lh = logoImg.height * scale;
        page.drawImage(logoImg, { x: margin, y: y - lh, width: lw, height: lh });
        logoEndX = margin + lw + 10;
        // Business name next to logo
        page.drawText(truck.name as string, {
          x: logoEndX, y: y - 16,
          font: fontBold, size: 18, color: black,
        });
        const sub = [truck.website_url, truck.social_instagram ? `@${truck.social_instagram}` : null]
          .filter(Boolean).join('  ·  ');
        if (sub) {
          page.drawText(sub, { x: logoEndX, y: y - 33, font: fontReg, size: 9, color: gray });
        }
      } catch { /* skip logo on error */ }
    }
  } else {
    page.drawText(truck.name as string, {
      x: margin, y: y - 16, font: fontBold, size: 20, color: black,
    });
  }

  // ── INVOICE label (top-right) ────────────────────────────────────────────────

  page.drawText('INVOICE', {
    x: width - margin - 80, y: y - 14,
    font: fontBold, size: 20, color: accent,
  });
  page.drawText(`#${invoiceNumber(booking_id)}`, {
    x: width - margin - 80, y: y - 30,
    font: fontReg, size: 10, color: gray,
  });
  page.drawText(`Issued: ${fmtDate(new Date().toISOString())}`, {
    x: width - margin - 80, y: y - 44,
    font: fontReg, size: 10, color: gray,
  });

  y -= 64;

  // ── Divider ──────────────────────────────────────────────────────────────────

  page.drawLine({ start: { x: margin, y }, end: { x: width - margin, y }, thickness: 1.5, color: accent });
  y -= 20;

  // ── Bill To + Event Details (two columns) ────────────────────────────────────

  const col2x = width / 2 + 10;
  const labelSize = 8;
  const bodySize = 10;

  // Bill To
  page.drawText('BILL TO', { x: margin, y, font: fontBold, size: labelSize, color: accent });
  y -= 14;
  page.drawText(booking.contact_name as string, { x: margin, y, font: fontBold, size: bodySize, color: black });
  y -= 13;
  page.drawText(booking.contact_email as string, { x: margin, y, font: fontReg, size: bodySize, color: gray });
  if (booking.contact_phone) {
    y -= 13;
    page.drawText(booking.contact_phone as string, { x: margin, y, font: fontReg, size: bodySize, color: gray });
  }

  // Event Details (right column)
  const eventY0 = y + (booking.contact_phone ? 40 : 27);
  page.drawText('EVENT DETAILS', { x: col2x, y: eventY0, font: fontBold, size: labelSize, color: accent });
  const eventLines: [string, string][] = [
    ['Type', booking.event_type as string],
    ['Date', fmtDate(booking.event_date as string)],
    ['Time', booking.event_time as string],
    ['Location', booking.event_location as string],
  ];
  if (booking.guest_count) eventLines.push(['Guests', String(booking.guest_count)]);
  if (booking.duration) eventLines.push(['Duration', booking.duration as string]);

  let ey = eventY0 - 14;
  for (const [label, value] of eventLines) {
    page.drawText(`${label}:`, { x: col2x, y: ey, font: fontBold, size: bodySize, color: gray });
    page.drawText(value, { x: col2x + 58, y: ey, font: fontReg, size: bodySize, color: black });
    ey -= 13;
  }

  y = Math.min(y, ey) - 20;

  // ── Financial summary ─────────────────────────────────────────────────────────

  page.drawText('FINANCIAL SUMMARY', { x: margin, y, font: fontBold, size: labelSize, color: accent });
  y -= 10;
  page.drawLine({ start: { x: margin, y }, end: { x: width - margin, y }, thickness: 0.5, color: lightGray });
  y -= 16;

  const drawRow = (label: string, amount: string, note: string | null, bold = false, color = black) => {
    page.drawText(label, { x: margin + 4, y, font: bold ? fontBold : fontReg, size: bodySize, color });
    if (note) page.drawText(note, { x: margin + 180, y, font: fontReg, size: 8, color: gray });
    page.drawText(amount, {
      x: width - margin - fontBold.widthOfTextAtSize(amount, bodySize),
      y, font: bold ? fontBold : fontReg, size: bodySize, color,
    });
    y -= 18;
  };

  if (estimate) {
    const estStatus = estimate.status as string;
    drawRow('Estimate', fmtMoney(estimate.amount as number),
      estStatus === 'paid' ? 'Paid' : estStatus === 'accepted' ? 'Accepted' : 'Sent');
  }
  if (deposit && deposit.status !== 'refunded') {
    const isPaid = deposit.status === 'paid';
    drawRow(
      isPaid ? 'Deposit (paid)' : 'Deposit (requested)',
      isPaid ? `-${fmtMoney(deposit.amount as number)}` : fmtMoney(deposit.amount as number),
      null, false, isPaid ? green : gray,
    );
  }
  if (invoice) {
    const invStatus = invoice.status as string;
    drawRow('Invoice', fmtMoney(invoice.amount as number),
      invStatus === 'paid' ? 'Paid' : 'Sent',
      false, invStatus === 'paid' ? green : black);
  }

  // Balance due
  const depositPaid = (deposit?.status === 'paid' ? (deposit.amount as number) : 0);
  const estimateAmt = estimate ? (estimate.amount as number) : 0;
  const invoiceAmt = invoice ? (invoice.amount as number) : 0;
  const balanceDue = invoice ? invoiceAmt : Math.max(0, estimateAmt - depositPaid);

  page.drawLine({ start: { x: margin, y: y + 4 }, end: { x: width - margin, y: y + 4 }, thickness: 0.5, color: lightGray });
  y -= 4;
  drawRow('BALANCE DUE', fmtMoney(balanceDue), null, true, balanceDue === 0 ? green : black);

  // ── Notes ────────────────────────────────────────────────────────────────────

  const notes = [estimate?.notes, invoice?.notes].filter(Boolean).join('\n');
  if (notes) {
    y -= 8;
    page.drawText('Notes:', { x: margin, y, font: fontBold, size: labelSize, color: gray });
    y -= 13;
    // Word-wrap notes at 80 chars
    const words = notes.split(' ');
    let line = '';
    for (const word of words) {
      if ((line + ' ' + word).length > 80) {
        page.drawText(line.trim(), { x: margin, y, font: fontReg, size: bodySize, color: gray });
        y -= 13;
        line = word;
      } else {
        line = line ? line + ' ' + word : word;
      }
    }
    if (line) page.drawText(line, { x: margin, y, font: fontReg, size: bodySize, color: gray });
    y -= 13;
  }

  // ── Footer ───────────────────────────────────────────────────────────────────

  const footerY = margin + 20;
  page.drawLine({ start: { x: margin, y: footerY + 14 }, end: { x: width - margin, y: footerY + 14 }, thickness: 0.5, color: lightGray });
  const thankYou = 'Thank you for your business!';
  page.drawText(thankYou, {
    x: (width - fontReg.widthOfTextAtSize(thankYou, 10)) / 2,
    y: footerY,
    font: fontReg, size: 10, color: gray,
  });
  page.drawText('Powered by Farlo', {
    x: (width - fontReg.widthOfTextAtSize('Powered by Farlo', 8)) / 2,
    y: footerY - 13,
    font: fontReg, size: 8, color: lightGray,
  });

  // ── Encode + return ──────────────────────────────────────────────────────────

  const pdfBytes = await pdfDoc.save();
  const base64 = btoa(
    new Uint8Array(pdfBytes).reduce((s, b) => s + String.fromCharCode(b), ''),
  );

  return new Response(
    JSON.stringify({ pdf_base64: base64, filename: `${truck.name} Invoice.pdf` }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});

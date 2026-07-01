// SafeSummit — Secure Admin API (Supabase Edge Function)
// จัดการรายชื่อ/อนุมัติลูกค้า โดยใช้ service_role key ฝั่ง server
// ป้องกันไม่ให้ข้อมูลลูกค้า (เลขบัตร ปชช. ฯลฯ) หลุดออกทาง publishable key
//
// Deploy:
//   supabase link --project-ref wucrvtgpjqjxxqarzcpv
//   supabase secrets set ADMIN_API_KEY=<ตั้งรหัสลับยาวๆ ของคุณเอง>
//   supabase functions deploy admin-customers --no-verify-jwt
//
// เรียกจาก client ด้วย header:  x-admin-key: <ADMIN_API_KEY>

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-admin-key',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405);

  // ── ตรวจรหัสลับของ admin ──
  const adminKey = req.headers.get('x-admin-key');
  if (!adminKey || adminKey !== Deno.env.get('ADMIN_API_KEY')) {
    return json({ error: 'unauthorized' }, 401);
  }

  // ── client ฝั่ง server ใช้ service_role (ข้าม RLS ได้) ──
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  let payload: { action?: string; id?: string };
  try { payload = await req.json(); } catch { return json({ error: 'bad json' }, 400); }
  const { action, id } = payload;

  try {
    if (action === 'list') {
      const { data, error } = await supabase
        .from('users')
        .select('*')
        .eq('role', 'customer')
        .order('created_at', { ascending: false });
      if (error) throw error;
      return json({ customers: data });
    }

    if (action === 'approve' || action === 'suspend') {
      if (!id) return json({ error: 'missing id' }, 400);
      const status = action === 'approve' ? 'approved' : 'suspended';
      const { error } = await supabase.from('users').update({ status }).eq('id', id);
      if (error) throw error;
      return json({ ok: true, id, status });
    }

    return json({ error: 'unknown action' }, 400);
  } catch (e) {
    return json({ error: String((e as Error).message || e) }, 500);
  }
});

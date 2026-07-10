// SafeSummit — Supabase Client
// ใช้ร่วมกันทุกหน้า

const SUPABASE_URL = 'https://wucrvtgpjqjxxqarzcpv.supabase.co';
const SUPABASE_KEY = 'sb_publishable_ZSUjn3Y0_8FnVI2RlI08FA_-DY4NsVe';

const { createClient } = supabase;
const db = createClient(SUPABASE_URL, SUPABASE_KEY);

// ─── TRIPS ───────────────────────────────────────────────
const Trips = {
  async getAll(filters = {}) {
    let q = db.from('trips').select(`
      *,
      organizers ( org_name, badge_tier )
    `).in('status', ['open', 'full', 'ongoing', 'completed']);

    if (filters.region)     q = q.eq('region', filters.region);
    if (filters.difficulty) q = q.eq('difficulty', filters.difficulty);
    if (filters.maxPrice)   q = q.lte('price_per_person', filters.maxPrice);
    if (filters.date)       q = q.eq('start_date', filters.date);
    if (filters.search)     q = q.ilike('name_th', `%${filters.search}%`);

    const { data, error } = await q.order('start_date');
    if (error) throw error;
    return data;
  },

  async getById(id) {
    const { data, error } = await db.from('trips').select(`
      *,
      organizers ( org_name, badge_tier, province, payment_qr_url ),
      trip_itinerary ( * )
    `).eq('id', id).maybeSingle();
    if (error) throw error;
    return data;
  }
};

// ─── PROFILE SAFETY NET ───────────────────────────────────
// บาง auth user ไม่มีแถวใน public.users (เช่น ตอนสมัคร insert พลาดแล้วถูกกลืน error)
// ทำให้ bookings.user_id ชน foreign key (bookings_user_id_fkey) → สร้างแถวให้อัตโนมัติ
async function ensureUserProfile(user) {
  if (!user) return;
  const { data: existing } = await db.from('users').select('id').eq('id', user.id).maybeSingle();
  if (existing) return;

  // ถ้าเป็นผู้จัด ให้ role ถูกต้อง
  let role = 'customer';
  try {
    const { data: org } = await db.from('organizers').select('id').eq('user_id', user.id).maybeSingle();
    if (org) role = 'organizer';
  } catch (_) {}

  const md = user.user_metadata || {};
  const { error } = await db.from('users').insert({
    id: user.id,
    email: user.email,
    password_hash: '-',              // Supabase Auth เก็บรหัสผ่านจริง (hash) ให้แล้ว
    full_name: md.full_name || user.email,
    nickname: md.nickname || null,
    phone: md.phone || null,
    role,
    status: 'approved',              // ล็อกอินผ่านมาแล้ว = ถือว่าใช้งานได้ (ตรงกับ login.html ที่ default เป็น approved เมื่อไม่มีแถว)
  });
  if (error) throw error;
}

// ตั้งสถานะ booking = pending_review ผ่าน RPC (ปลอดภัย) — fallback เป็น update ตรงถ้ายังไม่ได้รัน SQL RPC
async function _setBookingPending(bookingId, declared, slipPath, isBalance) {
  const { error } = await db.rpc('submit_booking_payment', {
    p_booking_id: bookingId, p_declared: declared, p_slip_url: slipPath, p_is_balance: isBalance
  });
  if (!error) return;
  // RPC ยังไม่มี (ก่อนรัน SQL Phase 8) → ใช้วิธีเดิมชั่วคราว
  if (error.code === 'PGRST202' || /function .*submit_booking_payment/i.test(error.message||'')) {
    const { error: uErr } = await db.from('bookings').update({
      slip_url: slipPath, slip_uploaded_at: new Date().toISOString(),
      declared_amount: declared, pay_status: 'pending_review',
      admin_note: isBalance ? '[จ่ายส่วนที่เหลือ]' : null
    }).eq('id', bookingId);
    if (uErr) throw uErr;
    return;
  }
  throw error;
}

// ─── BOOKINGS ─────────────────────────────────────────────
const Bookings = {
  // ที่นั่งที่ถูกจองไปแล้วของทริป (ลูกค้าอ่าน bookings คนอื่นไม่ได้ → ผ่าน RPC)
  async getTakenSeats(tripId) {
    try {
      const { data, error } = await db.rpc('trip_taken_seats', { p_trip_id: tripId });
      if (error) return [];
      return Array.isArray(data) ? data : [];
    } catch (_) { return []; }
  },

  async create({ tripId, seats, name, phone, note, seatNumbers }) {
    // 1. ดึงข้อมูลทริป
    const { data: trip, error: tErr } = await db
      .from('trips').select('price_per_person, capacity, booked_count, name_th, start_date')
      .eq('id', tripId).single();
    if (tErr) throw tErr;

    if (trip.booked_count + seats > trip.capacity)
      throw new Error('ที่นั่งไม่เพียงพอ');

    // กันจองที่นั่งซ้ำ: เช็คอีกครั้ง ณ ตอนสร้างจริง (กันคนอื่นเพิ่งจองไปพร้อมกัน)
    if (seatNumbers && seatNumbers.length) {
      const taken = await this.getTakenSeats(tripId);
      const clash = seatNumbers.filter(s => taken.includes(s));
      if (clash.length) {
        const e = new Error('ที่นั่ง ' + clash.join(', ') + ' เพิ่งถูกจองไปแล้ว กรุณาเลือกที่นั่งใหม่');
        e.code = 'SEAT_TAKEN';
        throw e;
      }
    }

    // 2. สร้าง booking_ref
    const now = new Date();
    const ref = `SS-${String(now.getFullYear()).slice(2)}${String(now.getMonth()+1).padStart(2,'0')}-${Math.random().toString(36).slice(2,7).toUpperCase()}`;

    // 3. Insert booking (ใช้ user_id จาก session หรือ null สำหรับ guest)
    const { data: session } = await db.auth.getSession();
    const authUser = session?.session?.user || null;
    const userId = authUser?.id || null;

    // กัน FK error: ถ้ายังไม่มีโปรไฟล์ใน public.users ให้สร้างให้ก่อน
    await ensureUserProfile(authUser);

    const { data, error } = await db.from('bookings').insert({
      user_id: userId,
      trip_id: tripId,
      booking_ref: ref,
      seats,
      price_snapshot: trip.price_per_person,
      total_price: trip.price_per_person * seats,
      status: 'pending',
      pay_status: 'unpaid',
      note: note || null,
      seat_numbers: (seatNumbers && seatNumbers.length) ? seatNumbers : null
    }).select().single();
    if (error) throw error;

    // booked_count อัปเดตอัตโนมัติด้วย DB trigger ฝั่ง Supabase (trg_booking_seats)
    return data;
  },

  async getMyBookings() {
    const { data, error } = await db.from('bookings').select(`
      *,
      trips ( name_th, start_date, duration_days, image_url, region )
    `).order('booked_at', { ascending: false });
    if (error) throw error;
    return data;
  },

  async getAll() {
    const { data, error } = await db.from('bookings').select(`
      *,
      trips ( name_th, start_date, region ),
      users ( full_name, phone, email )
    `).order('booked_at', { ascending: false });
    if (error) throw error;
    return data;
  },

  // ลูกค้าอัปสลิป + แจ้งยอด + LINE ID → pay_status='pending_review' (ผ่าน RPC กันตั้ง verified เอง)
  async submitPaymentSlip(bookingId, { file, declaredAmount, lineId }) {
    const { data: s } = await db.auth.getSession();
    const uid = s?.session?.user?.id;
    if (!uid) throw new Error('ยังไม่ได้เข้าสู่ระบบ');
    const ext = (file.name.split('.').pop() || 'jpg').toLowerCase();
    const path = `${uid}/${bookingId}.${ext}`;
    const { error: upErr } = await db.storage.from('slips')
      .upload(path, file, { upsert: true, contentType: file.type || 'image/jpeg' });
    if (upErr) throw upErr;
    await _setBookingPending(bookingId, declaredAmount, path, false);
    if (lineId) {
      try { await db.from('users').update({ line_id: lineId }).eq('id', uid); } catch(_) {}
    }
    return true;
  },

  // จ่ายส่วนที่เหลือ (ลูกค้าที่จ่ายมัดจำไว้) → กลับไป pending_review ให้ Admin ตรวจอีกรอบ
  async submitBalanceSlip(bookingId, { file, declaredTotal }) {
    const { data: s } = await db.auth.getSession();
    const uid = s?.session?.user?.id;
    if (!uid) throw new Error('ยังไม่ได้เข้าสู่ระบบ');
    const ext = (file.name.split('.').pop() || 'jpg').toLowerCase();
    const path = `${uid}/${bookingId}-balance.${ext}`;
    const { error: upErr } = await db.storage.from('slips')
      .upload(path, file, { upsert: true, contentType: file.type || 'image/jpeg' });
    if (upErr) throw upErr;
    await _setBookingPending(bookingId, declaredTotal, path, true);
    return true;
  },

  async getBookingPayment(bookingId) {
    const { data, error } = await db.from('bookings')
      .select('id, total_price, declared_amount, paid_amount, pay_status, slip_url, admin_note, seats')
      .eq('id', bookingId).maybeSingle();
    if (error) throw error;
    return data;
  },

  // ผู้จัดดูรายชื่อผู้จองของทริปตัวเอง (พร้อมชื่อเล่น เพื่อทำแผนผังที่นั่ง)
  async getByTrip(tripId) {
    const { data, error } = await db.from('bookings').select(`
      id, booking_ref, seats, seat_numbers, note, status, pay_status, total_price, booked_at,
      users ( full_name, nickname, phone )
    `).eq('trip_id', tripId).order('booked_at', { ascending: true });
    if (error) throw error;
    return data;
  }
};

// ─── ORGANIZERS ───────────────────────────────────────────
const Organizers = {
  async register({ orgName, province, expYears, bio, userId }) {
    const ref = 'ORG-' + Math.random().toString(36).slice(2,8).toUpperCase();
    const { data, error } = await db.from('organizers').insert({
      user_id: userId,
      org_name: orgName,
      province,
      exp_years: expYears,
      bio,
      reg_ref: ref,
      status: 'pending',
      badge_tier: 'unverified'
    }).select().single();
    if (error) throw error;
    return data;
  },

  async getMyProfile() {
    const { data: session } = await db.auth.getSession();
    if (!session?.session) return null;
    const uid = session.session.user.id;

    // ข้อมูลอ่อนไหว (เลขบัตร/บัญชีธนาคาร/ใบอนุญาต) ถูกปิดจาก anon+authenticated แล้ว
    // ผู้จัดอ่าน "แถวของตัวเอง" แบบเต็มผ่าน RPC security-definer
    try {
      const { data: rows, error: rpcErr } = await db.rpc('get_my_organizer');
      if (!rpcErr && Array.isArray(rows)) return rows[0] || null;
    } catch (_) { /* RPC ยังไม่มี (ก่อนรัน SQL) → ใช้วิธีเดิม */ }

    const { data, error } = await db.from('organizers')
      .select('*').eq('user_id', uid).maybeSingle();
    if (error) return null;
    return data;
  },

  // อัปโหลด QR พร้อมเพย์ → bucket payment-qr/{uid}/qr.ext → เซฟ URL ลง organizers.payment_qr_url
  async uploadQR(organizerId, file) {
    const { data: s } = await db.auth.getSession();
    const uid = s?.session?.user?.id;
    if (!uid) throw new Error('ยังไม่ได้เข้าสู่ระบบ');
    const ext = (file.name.split('.').pop() || 'png').toLowerCase();
    const path = `${uid}/qr.${ext}`;
    const { error: upErr } = await db.storage.from('payment-qr')
      .upload(path, file, { upsert: true, contentType: file.type || 'image/png' });
    if (upErr) throw upErr;
    const base = db.storage.from('payment-qr').getPublicUrl(path).data.publicUrl;
    const url = base + '?t=' + Date.now();   // cache-bust ให้รูปใหม่ขึ้นทันที
    const { error } = await db.from('organizers').update({ payment_qr_url: url }).eq('id', organizerId);
    if (error) throw error;
    return url;
  },

  async getQR(organizerId) {
    const { data, error } = await db.from('organizers')
      .select('payment_qr_url').eq('id', organizerId).maybeSingle();
    if (error) throw error;
    return data?.payment_qr_url || null;
  },

  async getAll() {
    const { data, error } = await db.from('organizers').select(`
      *, users ( full_name, email )
    `).order('created_at', { ascending: false });
    if (error) throw error;
    return data;
  },

  async updateStatus(id, status, adminNote = '') {
    const { error } = await db.from('organizers').update({
      status,
      note: adminNote,
      approved_at: status === 'approved' ? new Date().toISOString() : null
    }).eq('id', id);
    if (error) throw error;
  }
};

// ─── AUTH ─────────────────────────────────────────────────
const Auth = {
  async signUp(email, password, fullName, phone) {
    const { data, error } = await db.auth.signUp({
      email, password,
      options: { data: { full_name: fullName, phone } }
    });
    if (error) throw error;

    // insert into public.users — อย่ากลืน error ไม่งั้นได้บัญชี auth ที่ไม่มีโปรไฟล์ (ชน FK ตอนจอง)
    if (data.user) {
      const { error: insErr } = await db.from('users').insert({
        id: data.user.id,
        email,
        password_hash: '-',   // Supabase จัดการ auth เอง
        full_name: fullName,
        phone,
        role: 'customer'
      });
      if (insErr) console.error('users profile insert failed', insErr);
    }
    return data;
  },

  async signIn(email, password) {
    const { data, error } = await db.auth.signInWithPassword({ email, password });
    if (error) throw error;
    return data;
  },

  async signOut() {
    await db.auth.signOut();
  },

  async getUser() {
    const { data } = await db.auth.getUser();
    return data?.user || null;
  }
};

// ─── LOCATION IMAGE MATCHER ───────────────────────────────
// จับคู่ชื่อทริป/จังหวัด กับรูปในคลัง (fallback เมื่อผู้จัดไม่ได้อัปโหลดรูปเอง)
const LOCATION_IMAGES = [
  { img:'images/doichiangdao.png',    kw:['เชียงดาว'] },
  { img:'images/doiinthanon.webp',    kw:['อินทนนท์'] },
  { img:'images/kiwmaepan.jpg',       kw:['กิ่วแม่ปาน'] },
  { img:'images/doimaeya.jpg',        kw:['แม่ยะ'] },
  { img:'images/doiphaompok.jpg',     kw:['ผ้าห่มปก'] },
  { img:'images/phukradung.webp',     kw:['ภูกระดึง','กระดึง'] },
  { img:'images/phusoidao.webp',      kw:['ภูสอยดาว','สอยดาว'] },
  { img:'images/phuhinrongkla.jpg',   kw:['ร่องกล้า'] },
  { img:'images/phutabberk.jpg',      kw:['ทับเบิก'] },
  { img:'images/phulomloh.jpg',       kw:['ลมโล'] },
  { img:'images/phukamyao.jpg',       kw:['กามยาว','กำยาน'] },
  { img:'images/thilosu.jpg',         kw:['ทีลอซู'] },
  { img:'images/sannokvua.jpg',       kw:['สันนกวัว','นกวัว'] },
  { img:'images/khaoluangnakhon.jpg', kw:['เขาหลวงนคร'] },
  { img:'images/khaoluangprachuap.jpg', kw:['เขาหลวงประจวบ'] },
  { img:'images/khaosamroiyod.jpg',   kw:['สามร้อยยอด'] },
  { img:'images/khaosok.jpg',         kw:['เขาสก'] },
  { img:'images/khaophanom.jpg',      kw:['เขาพนม','พนมเบญจา'] },
  { img:'images/khaochang.jpg',       kw:['เขาช้าง','เขาช่อง'] },
  { img:'images/khaoluang.jpg',       kw:['เขาหลวง'] },
];
function matchLocationImg(t){
  if(!t) return null;
  const name = (t.name && (t.name.th || t.name.en)) || t.name || '';
  const hay = (name + ' ' + (t.prov || t.province || '')).replace(/\s+/g,'');
  for(const loc of LOCATION_IMAGES){
    if(loc.kw.some(k => hay.includes(k))) return loc.img;
  }
  return null;
}

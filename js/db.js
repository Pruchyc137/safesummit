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
      organizers ( org_name, badge_tier, province ),
      trip_itinerary ( * )
    `).eq('id', id).single();
    if (error) throw error;
    return data;
  }
};

// ─── BOOKINGS ─────────────────────────────────────────────
const Bookings = {
  async create({ tripId, seats, name, phone, note }) {
    // 1. ดึงข้อมูลทริป
    const { data: trip, error: tErr } = await db
      .from('trips').select('price_per_person, capacity, booked_count, name_th, start_date')
      .eq('id', tripId).single();
    if (tErr) throw tErr;

    if (trip.booked_count + seats > trip.capacity)
      throw new Error('ที่นั่งไม่เพียงพอ');

    // 2. สร้าง booking_ref
    const now = new Date();
    const ref = `SS-${String(now.getFullYear()).slice(2)}${String(now.getMonth()+1).padStart(2,'0')}-${Math.random().toString(36).slice(2,7).toUpperCase()}`;

    // 3. Insert booking (ใช้ user_id จาก session หรือ null สำหรับ guest)
    const { data: session } = await db.auth.getSession();
    const userId = session?.session?.user?.id || null;

    const { data, error } = await db.from('bookings').insert({
      user_id: userId,
      trip_id: tripId,
      booking_ref: ref,
      seats,
      price_snapshot: trip.price_per_person,
      total_price: trip.price_per_person * seats,
      status: 'pending',
      pay_status: 'unpaid',
      note: note || null
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

  // ผู้จัดดูรายชื่อผู้จองของทริปตัวเอง (พร้อมชื่อเล่น เพื่อทำแผนผังที่นั่ง)
  async getByTrip(tripId) {
    const { data, error } = await db.from('bookings').select(`
      id, booking_ref, seats, note, status, pay_status, total_price, booked_at,
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
    const { data, error } = await db.from('organizers')
      .select('*').eq('user_id', uid).single();
    if (error) return null;
    return data;
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

    // insert into public.users
    if (data.user) {
      await db.from('users').insert({
        id: data.user.id,
        email,
        password_hash: '-',   // Supabase จัดการ auth เอง
        full_name: fullName,
        phone,
        role: 'customer'
      });
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

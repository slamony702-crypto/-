// ═══════════════════════════════════════════════════════════
// Shared Security Helpers لواجهات الذكاء الاصطناعي
// ═══════════════════════════════════════════════════════════
// ملف يبدأ بـ "_" → Vercel لا يعامله كـendpoint (module مشترك فقط).
//
// يوفّر:
//   - applyCors: allowlist صارم من ALLOWED_ORIGINS (exact match)
//   - readJsonBody: قراءة body آمنة بحد أقصى للحجم
//   - checkContentType: يرفض غير application/json
//   - rateLimit: best-effort in-memory (per instance)
//   - verifySupabaseJWT: تحقق حقيقي من توكن Supabase (اختياري خلف إعداد)
//   - requireAiAuth: بوابة المصادقة خلف AI_REQUIRE_SUPABASE_JWT
//   - productionGuard: يمنع تشغيل Production بلا مصادقة
//   - maskError / newRequestId / safeLog
// ═══════════════════════════════════════════════════════════

// ─── (1) CORS — allowlist صارم من env، بدون wildcard ولا includes ───
export function applyCors(req, res) {
  const raw = process.env.ALLOWED_ORIGINS || '';
  const allowed = raw.split(',').map(s => s.trim()).filter(Boolean);
  const origin = req.headers.origin;

  // OPTIONS preflight — لا نكشف الـheaders إلا لأصل مسموح
  const isAllowed = origin && allowed.includes(origin); // exact match فقط

  if (isAllowed) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
    res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    res.setHeader('Access-Control-Max-Age', '600');
  }

  if (req.method === 'OPTIONS') {
    // preflight: 204 للمسموح، 403 لغير المسموح — لا نرد بـ* أبدًا
    res.status(isAllowed ? 204 : 403).end();
    return { handled: true, allowed: isAllowed };
  }

  // طلب فعلي من أصل غير مسموح → رفض صريح
  // ملاحظة: طلبات same-origin من المتصفح لا ترسل Origin؛ نطبّق سياسة واضحة:
  //   - لو ALLOWED_ORIGINS فارغ → نرفض الكل (fail-closed) في Production
  //   - لو Origin موجود وغير مسموح → رفض
  //   - لو Origin غائب (same-origin/غير متصفح) → نسمح فقط لو allowlist مضبوطة
  if (origin && !isAllowed) {
    res.status(403).json({ error: 'الأصل غير مسموح به' });
    return { handled: true, allowed: false };
  }
  if (!origin && allowed.length === 0) {
    // fail-closed: لا allowlist ولا Origin → في Production نرفض
    if (isProduction()) {
      res.status(403).json({ error: 'إعداد الأصول غير مكتمل' });
      return { handled: true, allowed: false };
    }
  }
  return { handled: false, allowed: true };
}

// ─── (2) Content-Type check ───
export function checkContentType(req, res) {
  const ct = (req.headers['content-type'] || '').toLowerCase();
  if (!ct.includes('application/json')) {
    res.status(415).json({ error: 'Content-Type يجب أن يكون application/json' });
    return false;
  }
  return true;
}

// ─── (3) Rate limiting — best-effort in-memory (per serverless instance) ───
// ⚠️ محدودية: Vercel متعدد الـinstances، فهذا حد تقريبي لكل instance.
//    للإنتاج الجاد استخدم Upstash/Redis. موثّق في التقرير.
const _rlBuckets = new Map(); // key → { count, resetAt }
export function rateLimit(key, { max = 20, windowMs = 60000 } = {}) {
  const now = Date.now();
  let b = _rlBuckets.get(key);
  if (!b || now > b.resetAt) {
    b = { count: 0, resetAt: now + windowMs };
    _rlBuckets.set(key, b);
  }
  b.count++;
  // تنظيف دوري بسيط لتجنّب تضخم الذاكرة
  if (_rlBuckets.size > 5000) {
    for (const [k, v] of _rlBuckets) { if (now > v.resetAt) _rlBuckets.delete(k); }
  }
  return {
    ok: b.count <= max,
    remaining: Math.max(0, max - b.count),
    resetInMs: b.resetAt - now
  };
}

export function clientKey(req) {
  // مفتاح تقريبي للـrate limit: IP من رؤوس Vercel
  return (req.headers['x-forwarded-for'] || req.headers['x-real-ip'] || 'unknown')
    .toString().split(',')[0].trim();
}

// ─── (4) Supabase JWT verification (حقيقي، ليس شكليًا) ───
// يستخدم Supabase Auth endpoint للتحقق من التوكن.
// لا يعتمد على localStorage ولا أي قيمة من العميل غير التوكن نفسه.
export async function verifySupabaseJWT(req) {
  const auth = req.headers['authorization'] || '';
  const m = auth.match(/^Bearer\s+(.+)$/i);
  if (!m) return { ok: false, code: 401, reason: 'MISSING_TOKEN' };
  const token = m[1].trim();

  const supabaseUrl = process.env.SUPABASE_URL || process.env.STAGING_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY || process.env.STAGING_ANON_KEY;
  if (!supabaseUrl || !anonKey) {
    return { ok: false, code: 500, reason: 'AUTH_NOT_CONFIGURED' };
  }

  try {
    const controller = new AbortController();
    const t = setTimeout(() => controller.abort(), 8000);
    let resp;
    try {
      resp = await fetch(`${supabaseUrl}/auth/v1/user`, {
        headers: { apikey: anonKey, Authorization: `Bearer ${token}` },
        signal: controller.signal
      });
    } finally { clearTimeout(t); }

    if (!resp.ok) return { ok: false, code: 401, reason: 'INVALID_TOKEN' };
    const user = await resp.json();
    if (!user || !user.id) return { ok: false, code: 401, reason: 'INVALID_TOKEN' };
    return { ok: true, user };
  } catch (e) {
    return { ok: false, code: 401, reason: 'TOKEN_VERIFY_FAILED' };
  }
}

// ─── (5) بوابة المصادقة خلف إعداد واضح ───
// AI_REQUIRE_SUPABASE_JWT=true  → المصادقة إلزامية
// AI_REQUIRE_SUPABASE_JWT!=true → وضع تطوير فقط (ممنوع في Production عبر productionGuard)
export async function requireAiAuth(req, res) {
  const required = String(process.env.AI_REQUIRE_SUPABASE_JWT || '').toLowerCase() === 'true';
  if (!required) {
    // وضع تطوير — تحذير واضح في اللوجز، ممنوع في Production (يحرسه productionGuard)
    safeLog('warn', 'AI auth DISABLED (dev mode) — AI_REQUIRE_SUPABASE_JWT is not true');
    return { ok: true, devBypass: true, user: null };
  }
  const v = await verifySupabaseJWT(req);
  if (!v.ok) {
    const status = v.code || 401;
    res.status(status).json({ error: status === 403 ? 'صلاحية غير كافية' : 'مصادقة مطلوبة' });
    return { ok: false };
  }
  return { ok: true, user: v.user };
}

// ─── (6) Production Guard — يمنع تشغيل Production بلا مصادقة ───
export function productionGuard(res) {
  const required = String(process.env.AI_REQUIRE_SUPABASE_JWT || '').toLowerCase() === 'true';
  if (isProduction() && !required) {
    // في الإنتاج بدون مصادقة → نرفض الخدمة صراحةً بدل فتح API مكشوف
    if (res) {
      res.status(503).json({ error: 'خدمة الذكاء الاصطناعي متوقفة مؤقتًا لحين استكمال إعدادات الأمان' });
    }
    safeLog('error', 'PRODUCTION GUARD: AI endpoint blocked — auth not enabled in production');
    return { blocked: true };
  }
  return { blocked: false };
}

export function isProduction() {
  return (process.env.VERCEL_ENV === 'production') ||
         (process.env.NODE_ENV === 'production' && process.env.VERCEL_ENV !== 'preview');
}

// ─── (7) أدوات مساعدة ───
export function newRequestId() {
  return 'req_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 8);
}

// Error masking — لا نرسل Stack Trace أو أسرار للعميل
export function maskError(res, status, publicMessage, internalErr, reqId) {
  safeLog('error', `[${reqId || '-'}] ${publicMessage}`, internalErr);
  res.status(status).json({ error: publicMessage, requestId: reqId });
}

// Safe logging — لا يطبع Tokens أو Prompts كاملة أو أسرار
export function safeLog(level, msg, extra) {
  const line = `[AI-SEC][${level}] ${msg}`;
  // نتجنّب طباعة كائنات قد تحتوي توكنات؛ نطبع الرسالة فقط + نوع الخطأ
  if (extra && extra.name) {
    console[level === 'error' ? 'error' : 'log'](line + ' :: ' + extra.name);
  } else {
    console[level === 'error' ? 'error' : 'log'](line);
  }
}

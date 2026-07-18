// ═══════════════════════════════════════════════════════════
// اختبارات أمان واجهات الذكاء الاصطناعي (Node، بلا إطار خارجي)
// ═══════════════════════════════════════════════════════════
// التشغيل:
//   node _reengineering/security/ai_endpoint_security.test.mjs
//
// يستدعي handlers الفعلية عبر mock للـreq/res — بلا شبكة حقيقية
// لمعظم الحالات. أي حالة تحتاج Supabase Auth حقيقي مُعلَّمة:
//   NOT EXECUTED — REQUIRES SUPABASE AUTH STAGING
// ═══════════════════════════════════════════════════════════

import agentHandler from '../../api/agent.js';
import rewriteHandler from '../../api/rewrite.js';

let pass = 0, fail = 0, skipped = 0;
function ok(name, cond, detail) {
  if (cond) { pass++; console.log(`✅ PASS: ${name}`); }
  else { fail++; console.log(`❌ FAIL: ${name}${detail ? ' :: ' + detail : ''}`); }
}
function skip(name, reason) { skipped++; console.log(`⏸ SKIPPED: ${name} — ${reason}`); }

// mock res
function mockRes() {
  return {
    _status: null, _json: null, _headers: {}, _ended: false,
    setHeader(k, v) { this._headers[k.toLowerCase()] = v; },
    status(c) { this._status = c; return this; },
    json(o) { this._json = o; this._ended = true; return this; },
    end() { this._ended = true; return this; }
  };
}
function mockReq({ method = 'POST', origin, contentType = 'application/json', body = {}, auth } = {}) {
  const headers = {};
  if (origin !== undefined) headers.origin = origin;
  if (contentType !== undefined) headers['content-type'] = contentType;
  if (auth !== undefined) headers.authorization = auth;
  headers['x-forwarded-for'] = '203.0.113.' + Math.floor(Math.random() * 250 + 1); // IP مختلف لتجنّب rate limit
  return { method, headers, body };
}

// ضبط بيئة الاختبار
process.env.ALLOWED_ORIGINS = 'https://app.example.com,http://localhost:3001';
process.env.GEMINI_API_KEY = 'test-key-not-real'; // لن نصل لـGemini في الحالات المُختبَرة
process.env.AI_REQUIRE_SUPABASE_JWT = 'false'; // dev mode لمعظم الاختبارات
delete process.env.VERCEL_ENV;
process.env.NODE_ENV = 'test';

console.log('════════════════════════════════════════════════════');
console.log('  AI Endpoint Security Tests');
console.log('════════════════════════════════════════════════════');

// ─── T1: Origin مسموح — لا يُرفض في مرحلة CORS ───
{
  const res = mockRes();
  await rewriteHandler(mockReq({ origin: 'https://app.example.com', body: { text: 'مرحبا بالعالم' } }), res);
  // قد يفشل لاحقًا عند Gemini (مفتاح وهمي) لكن ليس 403 CORS
  ok('T1 allowed origin passes CORS', res._status !== 403 || res._json?.error !== 'الأصل غير مسموح به',
     'status=' + res._status);
  ok('T1 sets exact Allow-Origin (not *)',
     res._headers['access-control-allow-origin'] === 'https://app.example.com',
     'got=' + res._headers['access-control-allow-origin']);
}

// ─── T2: Origin غير مسموح → 403 ───
{
  const res = mockRes();
  await rewriteHandler(mockReq({ origin: 'https://evil.example.com', body: { text: 'hi' } }), res);
  ok('T2 disallowed origin → 403', res._status === 403);
  ok('T2 no Allow-Origin header for evil origin',
     res._headers['access-control-allow-origin'] === undefined);
}

// ─── T3: لا wildcard في أي رد ───
{
  const res = mockRes();
  await agentHandler(mockReq({ origin: 'https://app.example.com', body: { contents: [{ role: 'user', parts: [{ text: 'x' }] }] } }), res);
  ok('T3 no wildcard CORS ever', res._headers['access-control-allow-origin'] !== '*');
}

// ─── T4: OPTIONS preflight صحيح ───
{
  const res = mockRes();
  await agentHandler(mockReq({ method: 'OPTIONS', origin: 'https://app.example.com' }), res);
  ok('T4 OPTIONS allowed → 204', res._status === 204 && res._ended);
  const res2 = mockRes();
  await agentHandler(mockReq({ method: 'OPTIONS', origin: 'https://evil.example.com' }), res2);
  ok('T4 OPTIONS disallowed → 403', res2._status === 403);
}

// ─── T5: Missing Bearer عند تفعيل JWT → 401 ───
{
  process.env.AI_REQUIRE_SUPABASE_JWT = 'true';
  process.env.SUPABASE_URL = 'https://fake.supabase.co';
  process.env.SUPABASE_ANON_KEY = 'anon-fake';
  const res = mockRes();
  await agentHandler(mockReq({ origin: 'https://app.example.com', body: { contents: [{ role: 'user', parts: [{ text: 'x' }] }] } }), res);
  ok('T5 missing Bearer (JWT required) → 401', res._status === 401, 'status=' + res._status);
  process.env.AI_REQUIRE_SUPABASE_JWT = 'false';
}

// ─── T6: Invalid Bearer → 401 (يحاول التحقق من Supabase وهمي فيفشل) ───
{
  process.env.AI_REQUIRE_SUPABASE_JWT = 'true';
  process.env.SUPABASE_URL = 'https://fake.supabase.co';
  process.env.SUPABASE_ANON_KEY = 'anon-fake';
  const res = mockRes();
  await agentHandler(mockReq({ origin: 'https://app.example.com', auth: 'Bearer invalid.token.here',
    body: { contents: [{ role: 'user', parts: [{ text: 'x' }] }] } }), res);
  ok('T6 invalid Bearer → 401', res._status === 401, 'status=' + res._status);
  process.env.AI_REQUIRE_SUPABASE_JWT = 'false';
}

// ─── T7: Valid Bearer — يحتاج Supabase Auth حقيقي ───
skip('T7 valid Bearer accepted', 'NOT EXECUTED — REQUIRES SUPABASE AUTH STAGING');

// ─── T8: مستخدم بلا صلاحية AI — يحتاج Auth + جدول صلاحيات ───
skip('T8 user without AI permission → 403', 'NOT EXECUTED — REQUIRES SUPABASE AUTH STAGING');

// ─── T9: Body أكبر من الحد → 400 ───
{
  const big = 'ا'.repeat(130000);
  const res = mockRes();
  await agentHandler(mockReq({ origin: 'https://app.example.com',
    body: { contents: [{ role: 'user', parts: [{ text: big }] }] } }), res);
  ok('T9 oversized body → 400', res._status === 400, 'status=' + res._status);
}

// ─── T10: Content-Type غير صحيح → 415 ───
{
  const res = mockRes();
  await rewriteHandler(mockReq({ origin: 'https://app.example.com', contentType: 'text/plain', body: { text: 'x' } }), res);
  ok('T10 wrong content-type → 415', res._status === 415, 'status=' + res._status);
}

// ─── T11: Rate limit → 429 بعد تجاوز الحد ───
{
  const fixedIp = '198.51.100.77';
  let got429 = false;
  for (let i = 0; i < 40; i++) {
    const req = mockReq({ origin: 'https://app.example.com', body: { text: 'x' } });
    req.headers['x-forwarded-for'] = fixedIp; // نفس IP
    const res = mockRes();
    await rewriteHandler(req, res);
    if (res._status === 429) { got429 = true; break; }
  }
  ok('T11 rate limit triggers 429', got429);
}

// ─── T12: Timeout — يحتاج شبكة حقيقية بطيئة ───
skip('T12 upstream timeout handled', 'NOT EXECUTED — REQUIRES LIVE GEMINI (timeout path)');

// ─── T13: extraInstructions يُرفض/يُتجاهل ───
{
  // نرسل extraInstructions خبيثة — يجب ألا تؤثر (الخادم يتجاهلها تمامًا)
  // نتحقق أن الحقل غير مقروء: الرد لا يعتمد عليه. هنا نتأكد أن الطلب لا يُقبل
  // كـسبب لتغيير السلوك — نفحص أن agent لا يقرأ extraInstructions إطلاقًا.
  const src = (await import('node:fs')).readFileSync(new URL('../../api/agent.js', import.meta.url), 'utf8');
  const readsExtra = /req\.body[^;]*extraInstructions|const\s*\{[^}]*extraInstructions[^}]*\}\s*=\s*req\.body/.test(src);
  ok('T13 server does not destructure extraInstructions from body', !readsExtra);
}

// ─── T14: prompt injection في الحقول لا يغير System Prompt ───
{
  // promptMode بقيمة خبيثة → يجب أن يسقط إلى default (لا يُحقن نص حر)
  const src = (await import('node:fs')).readFileSync(new URL('../../api/agent.js', import.meta.url), 'utf8');
  const usesAllowlist = /ALLOWED_PROMPT_MODES/.test(src) && /hasOwnProperty\.call\(ALLOWED_PROMPT_MODES/.test(src);
  ok('T14 promptMode restricted to server-side allowlist', usesAllowlist);
}

// ─── T15: Errors لا تكشف Keys أو Stack ───
{
  const src = (await import('node:fs')).readFileSync(new URL('../../api/agent.js', import.meta.url), 'utf8');
  const leaksModelErrors = /json\(\{\s*error:[^}]*model_errors/.test(src);
  ok('T15 agent does not send raw model_errors to client', !leaksModelErrors);
  const rsrc = (await import('node:fs')).readFileSync(new URL('../../api/rewrite.js', import.meta.url), 'utf8');
  const leaksErrMessage = /json\(\{\s*error:\s*err\.message/.test(rsrc);
  ok('T15 rewrite does not send err.message to client', !leaksErrMessage);
}

// ─── T16: Secrets لا تظهر في الكود (فحص ثابت) ───
{
  const files = ['../../api/agent.js', '../../api/rewrite.js', '../../api/_security.js'];
  let leaked = false;
  for (const f of files) {
    const src = (await import('node:fs')).readFileSync(new URL(f, import.meta.url), 'utf8');
    // بحث عن مفاتيح حقيقية محتملة (sb_secret, service_role, sk-, AIza...)
    if (/sb_secret_|service_role_key\s*=\s*['"][A-Za-z0-9]/.test(src) || /AIza[0-9A-Za-z_-]{30,}/.test(src)) leaked = true;
  }
  ok('T16 no hardcoded secrets in api files', !leaked);
}

// ─── T17: Production Guard يمنع تشغيل API دون JWT ───
{
  process.env.VERCEL_ENV = 'production';
  process.env.AI_REQUIRE_SUPABASE_JWT = 'false'; // معطّل في الإنتاج → يجب الحظر
  const res = mockRes();
  await agentHandler(mockReq({ origin: 'https://app.example.com',
    body: { contents: [{ role: 'user', parts: [{ text: 'x' }] }] } }), res);
  ok('T17 production + no-auth → 503 blocked', res._status === 503, 'status=' + res._status);
  delete process.env.VERCEL_ENV;
  process.env.NODE_ENV = 'test';
}

console.log('════════════════════════════════════════════════════');
console.log(`  النتيجة: PASS=${pass}  FAIL=${fail}  SKIPPED=${skipped}`);
console.log('════════════════════════════════════════════════════');
process.exit(fail > 0 ? 1 : 0);

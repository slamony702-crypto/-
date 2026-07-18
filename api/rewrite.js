// Vercel Serverless Function: يعيد صياغة النص العربي بأسلوب سهل واضح مهذّب
// المفتاح يعيش في Vercel Environment Variables (GEMINI_API_KEY) — لا يظهر في الكود العميل
//
// 🔒 أمان (security/api-hardening-phase1): CORS allowlist + rate limit + JWT scaffold
//    + size/content-type limits + error masking. لا wildcard CORS.

import {
  applyCors, checkContentType, rateLimit, clientKey,
  requireAiAuth, productionGuard, newRequestId, maskError
} from './_security.js';

export default async function handler(req, res) {
  const reqId = newRequestId();

  // (1) CORS allowlist
  const cors = applyCors(req, res);
  if (cors.handled) return;

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Only POST is allowed' });
  }

  // (2) Production Guard
  if (productionGuard(res).blocked) return;

  // (3) Content-Type
  if (!checkContentType(req, res)) return;

  // (4) Rate limit
  const rl = rateLimit('rewrite:' + clientKey(req), { max: 30, windowMs: 60000 });
  if (!rl.ok) {
    res.setHeader('Retry-After', Math.ceil(rl.resetInMs / 1000));
    return res.status(429).json({ error: 'طلبات كثيرة — حاول بعد قليل', requestId: reqId });
  }

  // (5) المصادقة
  const auth = await requireAiAuth(req, res);
  if (!auth.ok) return;

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    return maskError(res, 500, 'الخدمة غير مهيأة', { name: 'ConfigError' }, reqId);
  }

  const { text, mode } = req.body || {};
  if (!text || typeof text !== 'string' || text.trim().length < 2) {
    return res.status(400).json({ error: 'أدخل نصًا صحيحًا', requestId: reqId });
  }
  // حد أقصى لطول النص — يمنع استهلاك مفرط
  if (text.length > 8000) {
    return res.status(400).json({ error: 'النص طويل جدًا (الحد 8000 حرف)', requestId: reqId });
  }

  // أنماط مختلفة (نبدأ بواحد ونضيف لاحقًا لو حبيت)
  const stylePrompts = {
    default: 'أنت أداة إعادة صياغة نصوص عربية. مهمتك: تحويل النص المدخل إلى صياغة عربية فصيحة ومهذّبة مناسبة للتواصل المهني بين الزملاء. القواعد الصارمة: (1) اكتب النص المُعاد صياغته فقط ولا شيء آخر. (2) بالعربية 100%. (3) بدون أي تعليق أو تحليل أو ترجمة. (4) بدون علامات اقتباس. (5) بدون Markdown. (6) بدون بادئات مثل "إليك" أو "النص المعاد صياغته:". (7) الرد يجب أن يكون بحجم مشابه للنص الأصلي.',
    formal: 'أنت أداة إعادة صياغة نصوص عربية. مهمتك: تحويل النص المدخل إلى أسلوب رسمي احترافي مناسب لخطاب إداري. القواعد: (1) اكتب النص فقط. (2) بالعربية 100%. (3) بدون تعليقات أو Markdown أو علامات اقتباس أو بادئات.',
    friendly: 'أنت أداة إعادة صياغة نصوص عربية. مهمتك: تحويل النص إلى أسلوب ودود مختصر مناسب لواتساب. القواعد: (1) اكتب النص فقط. (2) بالعربية 100%. (3) بدون تعليقات أو Markdown أو علامات اقتباس أو بادئات.'
  };
  const styleKey = stylePrompts[mode] ? mode : 'default';
  const prompt = `${stylePrompts[styleKey]}\n\nالنص المدخل:\n"""\n${text}\n"""\n\nالنص المُعاد صياغته (بالعربية فقط، بدون أي إضافات):`;

  try {
    // نجرّب موديلات بالترتيب — أول واحد شغال بيتم استخدامه
    // نبدأ باللي شغال ومدعوم مع حساباتك، ثم fallback
    const models = ['gemini-flash-latest', 'gemini-flash-lite-latest', 'gemini-2.0-flash', 'gemini-1.5-flash'];
    let gRes, gData, usedModel;
    for (const model of models) {
      gRes = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{ role: 'user', parts: [{ text: prompt }] }],
          generationConfig: { temperature: 0.4, maxOutputTokens: 512, topP: 0.9 },
          safetySettings: [
            { category: 'HARM_CATEGORY_HARASSMENT', threshold: 'BLOCK_ONLY_HIGH' },
            { category: 'HARM_CATEGORY_HATE_SPEECH', threshold: 'BLOCK_ONLY_HIGH' },
            { category: 'HARM_CATEGORY_SEXUALLY_EXPLICIT', threshold: 'BLOCK_ONLY_HIGH' },
            { category: 'HARM_CATEGORY_DANGEROUS_CONTENT', threshold: 'BLOCK_ONLY_HIGH' }
          ]
        })
      }
    );
      gData = await gRes.json();
      // نجاح: خرج من اللوب
      if (gRes.ok) { usedModel = model; break; }
      // 429 (quota) أو 404 (موديل مش متاح): جرّب اللي بعده
      if (gRes.status === 429 || gRes.status === 404) continue;
      // أخطاء تانية: ارجعها فورًا
      break;
    }
    if (!gRes.ok) {
      // لا نُسرّب رسالة المزود الخام للعميل — رسالة عامة + تسجيل داخلي
      return maskError(res, gRes.status === 429 ? 429 : 502,
        gRes.status === 429 ? 'تم استهلاك الحصة — حاول لاحقًا' : 'تعذّرت إعادة الصياغة — حاول لاحقًا',
        { name: 'GeminiHttp' + gRes.status }, reqId);
    }
    const output = gData?.candidates?.[0]?.content?.parts?.[0]?.text || '';
    const cleaned = output.trim().replace(/^["""«»]+|["""«»]+$/g, '').trim();
    if (!cleaned) return res.status(502).json({ error: 'لم يتم توليد نص', requestId: reqId });
    return res.status(200).json({ text: cleaned, model: usedModel });
  } catch (err) {
    // لا Stack Trace للعميل
    return maskError(res, 502, 'فشل الاتصال بخدمة الذكاء الاصطناعي', err, reqId);
  }
}

// Vercel Serverless Function: يعيد صياغة النص العربي بأسلوب سهل واضح مهذّب
// المفتاح يعيش في Vercel Environment Variables (GEMINI_API_KEY) — لا يظهر في الكود العميل

export default async function handler(req, res) {
  // CORS للسماح للمنصة بالاتصال
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Only POST is allowed' });
  }

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    return res.status(500).json({ error: 'GEMINI_API_KEY غير مضبوط في إعدادات Vercel' });
  }

  const { text, mode } = req.body || {};
  if (!text || typeof text !== 'string' || text.trim().length < 2) {
    return res.status(400).json({ error: 'أدخل نصًا صحيحًا' });
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
      const msg = gData?.error?.message || 'خطأ من خدمة Gemini';
      return res.status(gRes.status === 429 ? 429 : 500).json({ error: msg });
    }
    const output = gData?.candidates?.[0]?.content?.parts?.[0]?.text || '';
    const cleaned = output.trim().replace(/^["""«»]+|["""«»]+$/g, '').trim();
    if (!cleaned) return res.status(500).json({ error: 'لم يتم توليد نص' });
    return res.status(200).json({ text: cleaned, model: usedModel });
  } catch (err) {
    return res.status(500).json({ error: err.message || 'فشل الاتصال بخدمة Gemini' });
  }
}

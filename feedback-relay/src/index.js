const REPO = 'canberkys/iPScanner';
const json = (body, status = 200) => Response.json(body, { status, headers: { 'Cache-Control': 'no-store' } });
const DAILY_LIMIT = 10;
// Public issues must not ping people or embed remote images chosen by an anonymous sender.
export const neutralize = (text) => text
  .replace(/@(?=[A-Za-z0-9-])/g, '@\u200b')
  .replace(/!\[/g, '!\\[')
  .replace(/<img\b/gi, '&lt;img');
// Optional per-IP daily cap; enabled when a FEEDBACK_DAILY KV namespace is bound.
async function underDailyLimit(kv, ip) {
  if (!kv) return true;
  const key = `daily:${new Date().toISOString().slice(0, 10)}:${ip}`;
  const count = Number(await kv.get(key)) || 0;
  if (count >= DAILY_LIMIT) return false;
  await kv.put(key, String(count + 1), { expirationTtl: 172800 });
  return true;
}
export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;
    if (path === '/health' && request.method === 'GET') return json({ ready: Boolean(env.GITHUB_PAT && env.FEEDBACK_LIMIT) });
    if (path !== '/feedback') return json({ error: 'Not found' }, 404);
    if (request.method !== 'POST') return json({ error: 'Use POST' }, 405);
    if (!env.GITHUB_PAT || !env.FEEDBACK_LIMIT) return json({ error: 'Feedback is temporarily unavailable. Please copy your report and try later.' }, 503);
    const ip = request.headers.get('CF-Connecting-IP');
    if (!ip) return json({ error: 'Invalid request' }, 400);
    if (!(await env.FEEDBACK_LIMIT.limit({ key: ip })).success) return json({ error: 'Too many reports. Please wait a minute.' }, 429);
    if (!request.headers.get('Content-Type')?.toLowerCase().startsWith('application/json')) return json({ error: 'JSON required' }, 415);
    // Bound the stream before JSON parsing, even without Content-Length.
    let bytes = 0, chunks = [];
    const reader = request.body?.getReader();
    if (!reader) return json({ error: 'Report required' }, 400);
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > 32768) { await reader.cancel(); return json({ error: 'Report too large' }, 413); }
      chunks.push(value);
    }
    let payload;
    try { payload = JSON.parse(await new Blob(chunks).text()); } catch { return json({ error: 'Invalid JSON' }, 400); }
    const { title, body, type } = payload ?? {};
    if (!['bug', 'feature'].includes(type) || typeof title !== 'string' || !title.trim() || title.length > 200 || typeof body !== 'string' || !body.trim() || body.length > 10000) return json({ error: 'Use a title up to 200 characters and a report up to 10,000 characters.' }, 400);
    if (!(await underDailyLimit(env.FEEDBACK_DAILY, ip))) return json({ error: 'Daily report limit reached. Please try again tomorrow.' }, 429);
    try {
      const response = await fetch(`https://api.github.com/repos/${REPO}/issues`, {
        method: 'POST', signal: AbortSignal.timeout(15000),
        headers: { 'Authorization': `Bearer ${env.GITHUB_PAT}`, 'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'ipscanner-feedback-relay', 'Content-Type': 'application/json' },
        body: JSON.stringify({ title: `[${type === 'bug' ? 'Bug' : 'Feature'}] ${neutralize(title.trim())}`, body: neutralize(body) + '\n\n_Submitted via iPScanner._', labels: [type === 'bug' ? 'bug' : 'enhancement'] })
      });
      if (!response.ok) return json({ error: 'GitHub could not accept this report. Please copy it and try later.' }, 502);
      const issue = await response.json();
      if (!Number.isInteger(issue.number)) return json({ error: 'Delivery could not be confirmed. Check the issue list before retrying.' }, 502);
      return json({ issueNumber: issue.number, issueURL: `https://github.com/${REPO}/issues/${issue.number}` });
    } catch {
      return json({ error: 'Delivery could not be confirmed. Check the issue list before retrying to avoid a duplicate.' }, 504);
    }
  }
};

import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker, { neutralize } from './index.js';
const env = { GITHUB_PAT: 'fake-test-only', FEEDBACK_LIMIT: { limit: async () => ({ success: true }) } };
const request = (payload) => new Request('https://example.test/feedback', { method: 'POST', headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '192.0.2.1' }, body: JSON.stringify(payload) });
test('fails closed without secret', async () => assert.equal((await worker.fetch(request({}), {})).status, 503));
test('rejects oversized streamed bodies', async () => assert.equal((await worker.fetch(request({ body: 'x'.repeat(33000) }), env)).status, 413));
test('enforces rate limit', async () => assert.equal((await worker.fetch(request({}), { ...env, FEEDBACK_LIMIT: { limit: async () => ({ success: false }) } })).status, 429));
test('rejects malformed fields', async () => assert.equal((await worker.fetch(request({ title: 1, body: 'hello', type: 'bug' }), env)).status, 400));
test('creates issue only in fixed repo, preserving reviewed text', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async (url, options) => {
    assert.equal(url, 'https://api.github.com/repos/canberkys/iPScanner/issues');
    assert.equal(JSON.parse(options.body).body, 'Reviewed text\n\n_Submitted via iPScanner._');
    return Response.json({ number: 42 });
  };
  try { const result = await worker.fetch(request({ title: 'Test', body: 'Reviewed text', type: 'bug', repo: 'other/repo' }), env); assert.equal((await result.json()).issueNumber, 42); }
  finally { globalThis.fetch = original; }
});
test('does not expose upstream errors or credentials', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async () => new Response('sensitive server detail', { status: 401 });
  try { const result = await worker.fetch(request({ title: 'Test', body: 'Text', type: 'feature' }), env); assert.equal(result.status, 502); assert.ok(!(await result.text()).includes('sensitive')); }
  finally { globalThis.fetch = original; }
});
test('neutralizes mentions and remote images', () => {
  const out = neutralize('Hi @octocat ![x](https://e.test/a.png) <IMG src=x> mail a@b');
  assert.ok(!/@[A-Za-z0-9]/.test(out));
  assert.ok(!out.includes('![') && !/<img/i.test(out));
});
test('labels issues by type', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async (_url, options) => { assert.deepEqual(JSON.parse(options.body).labels, ['enhancement']); return Response.json({ number: 7 }); };
  try { assert.equal((await worker.fetch(request({ title: 'T', body: 'B', type: 'feature' }), env)).status, 200); }
  finally { globalThis.fetch = original; }
});
test('enforces optional daily cap', async () => {
  const store = new Map();
  const kv = { get: async (k) => store.get(k) ?? null, put: async (k, v) => { store.set(k, v); } };
  const original = globalThis.fetch;
  globalThis.fetch = async () => Response.json({ number: 1 });
  try {
    for (let i = 0; i < 10; i++) assert.equal((await worker.fetch(request({ title: 'T', body: 'B', type: 'bug' }), { ...env, FEEDBACK_DAILY: kv })).status, 200);
    assert.equal((await worker.fetch(request({ title: 'T', body: 'B', type: 'bug' }), { ...env, FEEDBACK_DAILY: kv })).status, 429);
  } finally { globalThis.fetch = original; }
});

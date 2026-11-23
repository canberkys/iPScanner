# iPScanner feedback relay

The native app sends the previewed report to `/feedback`. The Worker creates a
PUBLIC issue in `canberkys/iPScanner`, with no end-user GitHub login. It does not
send an email or Telegram message. GitHub notification preferences control
notifications to repository watchers.

The Worker requires `GITHUB_PAT` as a Cloudflare secret. Create a fine-grained
GitHub token limited to `canberkys/iPScanner`, repository permission
**Issues: Read and write**. Set an expiration and rotate before it expires.
Enter the token only into the interactive secret prompt, never source or chat:

```sh
cd feedback-relay
npx wrangler secret put GITHUB_PAT
```

Deployment: `npx wrangler deploy`. Tests: `node --test`.
`GET /health` indicates whether required bindings exist, not whether GitHub has
accepted the token. Missing configuration fails closed with HTTP 503.

The endpoint is public. Cloudflare rate limiting allows 3 attempts per minute per
IP per Cloudflare location; this is not a global anti-abuse guarantee. Input is
limited to 32 KiB, titles to 200 UTF-16 code units and report bodies to 10,000.
No client-side secret is treated as authentication.

Reports are labeled `bug` or `enhancement`. `@mentions` and embedded images are
neutralized so an anonymous report cannot ping people or load remote images.
An optional daily cap of 10 reports per IP turns on when a KV namespace is bound
as `FEEDBACK_DAILY` (`npx wrangler kv namespace create FEEDBACK_DAILY`, then add
the binding to `wrangler.jsonc`). Without that binding the Worker behaves as before.

Request bodies and upstream
error contents are not logged by this Worker; observability is disabled.

The app waits for confirmed issue creation and preserves the draft on failure.
It does not retry automatically. A connection failure after GitHub accepts a
request can leave delivery uncertain; check the issue list before resubmitting.
Live delivery was verified with owner-approved test issue #11 on 2026-09-26.
The API returned HTTP 200; the issue body was independently checked and the test
issue was closed. GitHub email/push notification delivery was not verified.

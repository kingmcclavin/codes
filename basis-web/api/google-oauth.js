// Google sign-in helper for Cloud Sync (a Vercel serverless function).
//
// Google only gives a web page a long-lived sign-in when the final step uses
// the app's client secret, which can't live in the page. This function does
// just that step: it swaps a sign-in code (or a refresh token) for an access
// token and passes Google's answer back. It stores nothing, and notes never
// pass through it; the browser talks to Google Drive directly.
//
// Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in the Vercel project's
// Environment Variables.

module.exports = async (req, res) => {
  const clientId = process.env.GOOGLE_CLIENT_ID;
  const secret = process.env.GOOGLE_CLIENT_SECRET;
  res.setHeader('Cache-Control', 'no-store');

  if (req.method === 'GET') {
    res.status(200).json(clientId && secret ? { clientId } : { configured: false });
    return;
  }
  if (req.method !== 'POST') { res.status(405).json({ error: 'method_not_allowed' }); return; }
  if (!clientId || !secret) { res.status(503).json({ error: 'not_configured' }); return; }

  let body = req.body || {};
  if (typeof body === 'string') { try { body = JSON.parse(body); } catch { body = {}; } }

  const params = new URLSearchParams({ client_id: clientId, client_secret: secret });
  if (body.action === 'exchange' && body.code && body.code_verifier && body.redirect_uri) {
    params.set('grant_type', 'authorization_code');
    params.set('code', body.code);
    params.set('code_verifier', body.code_verifier);
    params.set('redirect_uri', body.redirect_uri);
  } else if (body.action === 'refresh' && body.refresh_token) {
    params.set('grant_type', 'refresh_token');
    params.set('refresh_token', body.refresh_token);
  } else {
    res.status(400).json({ error: 'bad_request' });
    return;
  }

  try {
    const r = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: params,
    });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) { res.status(r.status).json({ error: j.error || 'token_error', error_description: j.error_description }); return; }
    res.status(200).json({ access_token: j.access_token, expires_in: j.expires_in, refresh_token: j.refresh_token });
  } catch {
    res.status(502).json({ error: 'google_unreachable' });
  }
};

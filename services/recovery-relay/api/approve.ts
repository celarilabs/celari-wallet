// GET  /api/approve?rid=...&token=...  → Shows approval page
// POST /api/approve                     → Submits guardian key
//
// Guardian flow:
//   1. Receives email with link → GET renders approval page
//   2. Guardian enters their guardian_key → POST validates and stores

import type { VercelRequest, VercelResponse } from "@vercel/node";
import { recoveries } from "./initiate";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method === "GET") {
    return handleGet(req, res);
  }
  if (req.method === "POST") {
    return handlePost(req, res);
  }
  return res.status(405).json({ error: "Method not allowed" });
}

function handleGet(req: VercelRequest, res: VercelResponse) {
  const { rid, token } = req.query;

  if (!rid || !token) {
    return res.status(400).send("Invalid link");
  }

  const recovery = recoveries.get(rid as string);
  if (!recovery) {
    return res.status(404).send("Recovery not found or expired");
  }

  const guardian = recovery.guardians.find((g) => g.token === token);
  if (!guardian) {
    return res.status(403).send("Invalid token");
  }

  if (guardian.approved) {
    return res.status(200).send(approvedPage());
  }

  // Render approval page
  return res.status(200).send(approvalPage(rid as string, token as string, recovery.accountAddress));
}

async function handlePost(req: VercelRequest, res: VercelResponse) {
  const { recoveryId, token, guardianKey } = req.body;

  if (!recoveryId || !token || !guardianKey) {
    return res.status(400).json({ error: "Missing fields" });
  }

  const recovery = recoveries.get(recoveryId);
  if (!recovery) {
    return res.status(404).json({ error: "Recovery not found or expired" });
  }

  const guardian = recovery.guardians.find((g) => g.token === token);
  if (!guardian) {
    return res.status(403).json({ error: "Invalid token" });
  }

  // Store the guardian key (will be verified on-chain later)
  guardian.guardianKey = guardianKey;
  guardian.approved = true;

  const approvedCount = recovery.guardians.filter((g) => g.approved).length;

  return res.status(200).json({
    success: true,
    approvedCount,
    thresholdMet: approvedCount >= recovery.threshold,
  });
}

function approvalPage(rid: string, token: string, accountAddress: string): string {
  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Celari — Guardian Approval</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'SF Mono', monospace; background: #0a0a0a; color: #e0d5c8; padding: 32px; }
    .container { max-width: 480px; margin: 0 auto; }
    h1 { color: #c4956a; font-size: 18px; letter-spacing: 3px; margin-bottom: 24px; }
    .label { color: #666; font-size: 11px; letter-spacing: 2px; margin-bottom: 4px; }
    .address { background: #1a1a1a; padding: 12px; font-size: 12px; word-break: break-all; border: 1px solid #333; margin-bottom: 24px; }
    input { width: 100%; background: #1a1a1a; border: 1px solid #333; color: #e0d5c8; padding: 12px; font-family: monospace; font-size: 14px; margin-bottom: 16px; }
    input:focus { outline: none; border-color: #c4956a; }
    button { width: 100%; background: #c4956a; color: #0a0a0a; border: none; padding: 14px; font-family: monospace; font-size: 14px; font-weight: bold; letter-spacing: 2px; cursor: pointer; }
    button:hover { background: #d4a57a; }
    button:disabled { opacity: 0.5; cursor: not-allowed; }
    .status { margin-top: 16px; font-size: 12px; }
    .success { color: #4caf50; }
    .error { color: #f44336; }
  </style>
</head>
<body>
  <div class="container">
    <h1>GUARDIAN APPROVAL</h1>
    <div class="label">ACCOUNT</div>
    <div class="address">${accountAddress}</div>
    <div class="label">GUARDIAN KEY</div>
    <input type="text" id="guardianKey" placeholder="Enter your guardian key" />
    <button id="approveBtn" onclick="approve()">APPROVE RECOVERY</button>
    <div id="status" class="status"></div>
  </div>
  <script>
    async function approve() {
      const key = document.getElementById('guardianKey').value.trim();
      if (!key) return;
      const btn = document.getElementById('approveBtn');
      const status = document.getElementById('status');
      btn.disabled = true;
      btn.textContent = 'APPROVING...';
      try {
        const resp = await fetch('/api/approve', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            recoveryId: '${rid}',
            token: '${token}',
            guardianKey: key,
          }),
        });
        const data = await resp.json();
        if (data.success) {
          status.className = 'status success';
          status.textContent = data.thresholdMet
            ? 'Approved! Threshold met — recovery will proceed after 24h time-lock.'
            : 'Approved! Waiting for more guardians to approve.';
          btn.textContent = 'APPROVED';
        } else {
          throw new Error(data.error);
        }
      } catch (e) {
        status.className = 'status error';
        status.textContent = 'Error: ' + e.message;
        btn.disabled = false;
        btn.textContent = 'APPROVE RECOVERY';
      }
    }
  </script>
</body>
</html>`;
}

function approvedPage(): string {
  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Celari — Already Approved</title>
  <style>
    body { font-family: monospace; background: #0a0a0a; color: #4caf50; display: flex; align-items: center; justify-content: center; height: 100vh; }
  </style>
</head>
<body>
  <div style="text-align: center;">
    <h2>Already Approved</h2>
    <p>You have already approved this recovery request.</p>
  </div>
</body>
</html>`;
}

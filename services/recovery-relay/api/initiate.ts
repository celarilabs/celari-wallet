// POST /api/initiate
// Starts a recovery process and sends approval emails to guardians.
//
// Body: {
//   accountAddress: string,
//   newPubKeyX: string,
//   newPubKeyY: string,
//   guardians: [{ email: string, index: number }]
// }
//
// Response: { recoveryId: string }

import type { VercelRequest, VercelResponse } from "@vercel/node";
import { Resend } from "resend";
import crypto from "crypto";
import { setRecovery } from "./_redis";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const { accountAddress, newPubKeyX, newPubKeyY, guardians } = req.body;

  if (!accountAddress || !newPubKeyX || !newPubKeyY || !guardians?.length) {
    return res.status(400).json({ error: "Missing required fields" });
  }

  const recoveryId = crypto.randomUUID();
  const resend = new Resend(process.env.RESEND_API_KEY);

  const guardianEntries = [];

  for (const g of guardians) {
    const token = crypto.randomBytes(32).toString("hex");

    guardianEntries.push({
      email: g.email,
      index: g.index,
      token,
      approved: false,
    });

    // Send approval email
    const approveUrl = `${process.env.RELAY_BASE_URL || "https://recovery.celariwallet.com"}/api/approve?rid=${recoveryId}&token=${token}`;

    await resend.emails.send({
      from: "Celari Wallet <recovery@celariwallet.com>",
      to: g.email,
      subject: "Recovery Approval Requested — Celari Wallet",
      html: `
        <div style="font-family: monospace; max-width: 600px; margin: 0 auto; background: #0a0a0a; color: #e0d5c8; padding: 32px;">
          <h2 style="color: #c4956a;">Celari Wallet Recovery</h2>
          <p>A recovery has been requested for account:</p>
          <code style="background: #1a1a1a; padding: 8px 12px; display: block; word-break: break-all;">
            ${accountAddress}
          </code>
          <p style="margin-top: 24px;">
            If you recognize this request and want to approve the recovery,
            click the button below and enter your guardian key.
          </p>
          <a href="${approveUrl}" style="
            display: inline-block;
            background: #c4956a;
            color: #0a0a0a;
            padding: 12px 24px;
            text-decoration: none;
            font-weight: bold;
            margin-top: 16px;
          ">APPROVE RECOVERY</a>
          <p style="margin-top: 24px; color: #666; font-size: 12px;">
            If you did not expect this email, do not click the link.
            This link expires in 24 hours.
          </p>
        </div>
      `,
    });
  }

  await setRecovery(recoveryId, {
    accountAddress,
    newPubKeyX,
    newPubKeyY,
    guardians: guardianEntries,
    createdAt: Date.now(),
    threshold: 2,
  });

  return res.status(200).json({ recoveryId });
}

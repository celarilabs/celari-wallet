// GET /api/status?rid=...
// Returns the current state of a recovery request.
//
// Response: {
//   accountAddress: string,
//   approvedCount: number,
//   threshold: number,
//   thresholdMet: boolean,
//   guardianKeys: string[] (only when threshold met),
//   newPubKeyX: string,
//   newPubKeyY: string,
//   createdAt: number,
//   expiresAt: number,
// }

import type { VercelRequest, VercelResponse } from "@vercel/node";
import { recoveries } from "./initiate";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "GET") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const { rid } = req.query;

  if (!rid) {
    return res.status(400).json({ error: "Missing recoveryId" });
  }

  const recovery = recoveries.get(rid as string);
  if (!recovery) {
    return res.status(404).json({ error: "Recovery not found or expired" });
  }

  const approvedCount = recovery.guardians.filter((g) => g.approved).length;
  const thresholdMet = approvedCount >= recovery.threshold;

  const response: Record<string, unknown> = {
    accountAddress: recovery.accountAddress,
    approvedCount,
    threshold: recovery.threshold,
    thresholdMet,
    newPubKeyX: recovery.newPubKeyX,
    newPubKeyY: recovery.newPubKeyY,
    createdAt: recovery.createdAt,
    expiresAt: recovery.createdAt + 24 * 60 * 60 * 1000,
  };

  // Only expose guardian keys when threshold is met
  // These are needed for the on-chain initiate_recovery call
  if (thresholdMet) {
    response.guardianKeys = recovery.guardians
      .filter((g) => g.approved && g.guardianKey)
      .map((g) => g.guardianKey);
  }

  return res.status(200).json(response);
}

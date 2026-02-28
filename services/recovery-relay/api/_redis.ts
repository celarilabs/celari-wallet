import { Redis } from "@upstash/redis";

const redis = Redis.fromEnv();

const TTL_SECONDS = 24 * 60 * 60; // 24 hours

export interface RecoveryData {
  accountAddress: string;
  newPubKeyX: string;
  newPubKeyY: string;
  guardians: {
    email: string;
    index: number;
    token: string;
    approved: boolean;
    guardianKey?: string;
  }[];
  createdAt: number;
  threshold: number;
}

function key(id: string) {
  return `recovery:${id}`;
}

export async function getRecovery(id: string): Promise<RecoveryData | null> {
  return redis.get<RecoveryData>(key(id));
}

export async function setRecovery(id: string, data: RecoveryData): Promise<void> {
  await redis.set(key(id), data, { ex: TTL_SECONDS });
}

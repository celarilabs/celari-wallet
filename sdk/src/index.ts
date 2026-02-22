/**
 * @celari/sdk — Celari Wallet SDK for Aztec Network
 *
 * Connect dApps to the Celari Wallet browser extension.
 *
 * @example
 * ```ts
 * import { connectCelari, isCelariAvailable } from "@celari/sdk";
 *
 * if (await isCelariAvailable({ chainId: 31337, version: 1 })) {
 *   const { wallet } = await connectCelari({
 *     chainInfo: { chainId: 31337, version: 1 },
 *     appId: "my-dapp",
 *   });
 *   const accounts = await wallet.getAccounts();
 * }
 * ```
 */

export { connectCelari, isCelariAvailable } from "./connect.js";
export type { ConnectOptions, ConnectResult } from "./connect.js";

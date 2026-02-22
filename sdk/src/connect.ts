/**
 * Celari Wallet SDK — Connect Helper
 *
 * Convenience function to discover and connect to Celari Wallet
 * using the official @aztec/wallet-sdk WalletManager.
 */

import type { Wallet } from "@aztec/aztec.js/wallet";
import { Fr } from "@aztec/aztec.js/fields";
import { WalletManager } from "@aztec/wallet-sdk/manager";

const CELARI_WALLET_ID = "celari-wallet";

export interface ConnectOptions {
  /** Aztec chain info for discovery filtering */
  chainInfo: { chainId: number | bigint; version: number | bigint };
  /** Application identifier sent to the wallet */
  appId?: string;
  /** Discovery timeout in milliseconds (default: 3000) */
  timeout?: number;
}

export interface ConnectResult {
  wallet: Wallet;
  walletInfo: {
    id: string;
    name: string;
    icon: string;
    version?: string;
  };
}

function toChainInfo(input: ConnectOptions["chainInfo"]) {
  return {
    chainId: new Fr(input.chainId),
    version: new Fr(input.version),
  };
}

/**
 * Discover and connect to Celari Wallet.
 *
 * @example
 * ```ts
 * import { connectCelari } from "@celari/sdk";
 *
 * const { wallet } = await connectCelari({
 *   chainInfo: { chainId: 31337, version: 1 },
 *   appId: "my-dapp",
 * });
 *
 * const accounts = await wallet.getAccounts();
 * ```
 */
export async function connectCelari(options: ConnectOptions): Promise<ConnectResult> {
  const { chainInfo: rawChainInfo, appId = "celari-dapp", timeout = 3000 } = options;
  const chainInfo = toChainInfo(rawChainInfo);

  const manager = WalletManager.configure({
    extensions: {
      enabled: true,
      allowList: [CELARI_WALLET_ID],
    },
  });

  const wallets = await manager.getAvailableWallets({
    chainInfo,
    timeout,
  });

  const celariProvider = wallets.find((w) => w.id === CELARI_WALLET_ID);
  if (!celariProvider) {
    throw new Error(
      "Celari Wallet not found. Make sure the extension is installed and enabled.",
    );
  }

  const wallet = await celariProvider.connect(appId);

  return {
    wallet,
    walletInfo: {
      id: celariProvider.id,
      name: celariProvider.name,
      icon: celariProvider.icon ?? "",
      version: celariProvider.metadata?.version as string | undefined,
    },
  };
}

/**
 * Check if Celari Wallet is available (installed and responding to discovery).
 */
export async function isCelariAvailable(
  rawChainInfo: { chainId: number | bigint; version: number | bigint },
  timeout = 2000,
): Promise<boolean> {
  try {
    const chainInfo = toChainInfo(rawChainInfo);
    const manager = WalletManager.configure({
      extensions: { enabled: true, allowList: [CELARI_WALLET_ID] },
    });
    const wallets = await manager.getAvailableWallets({ chainInfo, timeout });
    return wallets.some((w) => w.id === CELARI_WALLET_ID);
  } catch {
    return false;
  }
}

// Celari Token Bridge -- L2 Contract (Aztec v4.0.4)
//
// Handles claiming of tokens deposited on L1 and initiating withdrawals back to L1.
// Works with the CelariBridgePortal on Ethereum (Sepolia) and BridgedToken on Aztec.

mod config;

use aztec::macros::aztec;

#[aztec]
pub contract CelariTokenBridge {
    use crate::config::Config;

    use aztec::{
        protocol::{
            address::{AztecAddress, EthAddress},
            hash::sha256_to_field,
            traits::ToField,
        },
        state_vars::PublicImmutable,
    };

    use bridged_token::BridgedToken;

    use aztec::macros::{
        functions::{external, initializer, view},
        storage::storage,
    };

    // --- Storage ---

    #[storage]
    struct Storage<Context> {
        config: PublicImmutable<Config, Context>,
    }

    // --- Constructor ---

    #[external("public")]
    #[initializer]
    fn constructor(token: AztecAddress, portal_address: EthAddress) {
        self.storage.config.initialize(Config { token, portal: portal_address });
    }

    // --- Getters ---

    #[external("public")]
    #[view]
    fn get_config() -> pub Config {
        self.storage.config.read()
    }

    // --- Claim Public (L1 -> L2 Public Balance) ---

    #[external("public")]
    fn claim_public(
        l1_token: EthAddress,
        to: AztecAddress,
        amount: Field,
        secret: Field,
        leaf_index: Field,
    ) {
        let content_hash = compute_deposit_content_hash(l1_token, amount, to, secret);
        let config = self.storage.config.read();

        self.context.consume_l1_to_l2_message(
            content_hash,
            secret,
            config.portal,
            leaf_index,
        );

        self.call(BridgedToken::at(config.token).mint_public(to, amount));
    }

    // --- Claim Private (L1 -> L2 Private Balance) ---

    #[external("public")]
    fn claim_private(
        l1_token: EthAddress,
        secret_for_redeeming_minted_notes: Field,
        amount: Field,
        secret: Field,
        leaf_index: Field,
    ) {
        let content_hash = compute_deposit_content_hash(
            l1_token,
            amount,
            AztecAddress::zero(),
            secret,
        );
        let config = self.storage.config.read();

        self.context.consume_l1_to_l2_message(
            content_hash,
            secret,
            config.portal,
            leaf_index,
        );

        self.call(BridgedToken::at(config.token).mint_private(secret_for_redeeming_minted_notes, amount));
    }

    // --- Exit to L1 (Public) ---

    #[external("public")]
    fn exit_to_l1_public(
        l1_token: EthAddress,
        recipient: EthAddress,
        amount: Field,
        caller_on_l1: EthAddress,
        authwit_nonce: Field,
    ) {
        let config = self.storage.config.read();

        let content_hash = compute_withdraw_content_hash(
            l1_token,
            amount,
            recipient,
            caller_on_l1,
        );
        self.context.message_portal(config.portal, content_hash);

        self.call(BridgedToken::at(config.token).burn_public(
            self.context.maybe_msg_sender().unwrap(),
            amount,
            authwit_nonce,
        ));
    }

    // --- Exit to L1 (Private) ---

    #[external("private")]
    fn exit_to_l1_private(
        token: AztecAddress,
        l1_token: EthAddress,
        recipient: EthAddress,
        amount: Field,
        caller_on_l1: EthAddress,
        authwit_nonce: Field,
    ) {
        let config = self.storage.config.read();
        assert(config.token.eq(token), "Token address mismatch");

        let content_hash = compute_withdraw_content_hash(
            l1_token,
            amount,
            recipient,
            caller_on_l1,
        );
        self.context.message_portal(config.portal, content_hash);

        self.call(BridgedToken::at(token).burn_private(
            self.context.maybe_msg_sender().unwrap(),
            amount,
            authwit_nonce,
        ));
    }

    // --- Content Hash Helpers ---

    #[contract_library_method]
    fn compute_deposit_content_hash(
        l1_token: EthAddress,
        amount: Field,
        to: AztecAddress,
        secret_hash: Field,
    ) -> Field {
        let mut hash_bytes: [u8; 128] = [0; 128];

        let token_bytes: [u8; 32] = l1_token.to_field().to_be_bytes();
        for i in 0..32 {
            hash_bytes[i] = token_bytes[i];
        }

        let amount_bytes: [u8; 32] = amount.to_be_bytes();
        for i in 0..32 {
            hash_bytes[32 + i] = amount_bytes[i];
        }

        let to_bytes: [u8; 32] = to.to_field().to_be_bytes();
        for i in 0..32 {
            hash_bytes[64 + i] = to_bytes[i];
        }

        let secret_bytes: [u8; 32] = secret_hash.to_be_bytes();
        for i in 0..32 {
            hash_bytes[96 + i] = secret_bytes[i];
        }

        sha256_to_field(hash_bytes)
    }

    #[contract_library_method]
    fn compute_withdraw_content_hash(
        l1_token: EthAddress,
        amount: Field,
        recipient: EthAddress,
        caller_on_l1: EthAddress,
    ) -> Field {
        let mut hash_bytes: [u8; 128] = [0; 128];

        let token_bytes: [u8; 32] = l1_token.to_field().to_be_bytes();
        for i in 0..32 {
            hash_bytes[i] = token_bytes[i];
        }

        let amount_bytes: [u8; 32] = amount.to_be_bytes();
        for i in 0..32 {
            hash_bytes[32 + i] = amount_bytes[i];
        }

        let recipient_bytes: [u8; 32] = recipient.to_field().to_be_bytes();
        for i in 0..32 {
            hash_bytes[64 + i] = recipient_bytes[i];
        }

        let caller_bytes: [u8; 32] = caller_on_l1.to_field().to_be_bytes();
        for i in 0..32 {
            hash_bytes[96 + i] = caller_bytes[i];
        }

        sha256_to_field(hash_bytes)
    }
}

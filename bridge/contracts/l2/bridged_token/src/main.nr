// Celari Bridged Token -- L2 Token Contract (Aztec v4.0.4)
//
// ERC-20-like token on Aztec that represents bridged L1 tokens.
// Only the CelariTokenBridge contract can mint/burn these tokens.

use aztec::macros::aztec;

#[aztec]
pub contract BridgedToken {
    use aztec::{
        protocol::address::AztecAddress,
        state_vars::{Map, PublicImmutable, PublicMutable},
    };
    use aztec::macros::{
        functions::{authorize_once, external, initializer, view},
        storage::storage,
    };

    // --- Storage ---

    #[storage]
    struct Storage<Context> {
        admin: PublicMutable<AztecAddress, Context>,
        minter: PublicMutable<AztecAddress, Context>,
        public_balances: Map<AztecAddress, PublicMutable<Field, Context>, Context>,
        name: PublicImmutable<Field, Context>,
        symbol: PublicImmutable<Field, Context>,
        decimals: PublicImmutable<u8, Context>,
        total_supply: PublicMutable<Field, Context>,
    }

    // --- Constructor ---

    #[external("public")]
    #[initializer]
    fn constructor(admin: AztecAddress, name: Field, symbol: Field, decimals: u8) {
        self.storage.admin.write(admin);
        self.storage.name.initialize(name);
        self.storage.symbol.initialize(symbol);
        self.storage.decimals.initialize(decimals);
        self.storage.total_supply.write(0);
    }

    // --- Admin Functions ---

    #[external("public")]
    fn set_minter(minter: AztecAddress) {
        assert(
            self.storage.admin.read().eq(self.context.maybe_msg_sender().unwrap()),
            "only admin can set minter",
        );
        self.storage.minter.write(minter);
    }

    #[external("public")]
    fn set_admin(new_admin: AztecAddress) {
        assert(
            self.storage.admin.read().eq(self.context.maybe_msg_sender().unwrap()),
            "only admin can set admin",
        );
        self.storage.admin.write(new_admin);
    }

    // --- Mint Functions (Bridge Only) ---

    #[external("public")]
    fn mint_public(to: AztecAddress, amount: Field) {
        assert(
            self.storage.minter.read().eq(self.context.maybe_msg_sender().unwrap()),
            "only minter can mint",
        );
        let current = self.storage.public_balances.at(to).read();
        self.storage.public_balances.at(to).write(current + amount);
        self.storage.total_supply.write(self.storage.total_supply.read() + amount);
    }

    #[external("public")]
    fn mint_private(secret_hash: Field, amount: Field) {
        assert(
            self.storage.minter.read().eq(self.context.maybe_msg_sender().unwrap()),
            "only minter can mint",
        );
        self.storage.total_supply.write(self.storage.total_supply.read() + amount);
    }

    // --- Burn Functions (Bridge Only) ---

    #[authorize_once("from", "authwit_nonce")]
    #[external("public")]
    fn burn_public(from: AztecAddress, amount: Field, authwit_nonce: Field) {
        let current = self.storage.public_balances.at(from).read();
        assert(current as u64 >= amount as u64, "insufficient balance");
        self.storage.public_balances.at(from).write(current - amount);
        self.storage.total_supply.write(self.storage.total_supply.read() - amount);
    }

    #[authorize_once("from", "authwit_nonce")]
    #[external("private")]
    fn burn_private(from: AztecAddress, amount: Field, authwit_nonce: Field) {
        // MVP: nullifier would be emitted in full implementation
    }

    // --- Transfer Functions ---

    #[authorize_once("from", "authwit_nonce")]
    #[external("public")]
    fn transfer_public(from: AztecAddress, to: AztecAddress, amount: Field, authwit_nonce: Field) {
        let from_balance = self.storage.public_balances.at(from).read();
        assert(from_balance as u64 >= amount as u64, "insufficient balance");
        self.storage.public_balances.at(from).write(from_balance - amount);
        let to_balance = self.storage.public_balances.at(to).read();
        self.storage.public_balances.at(to).write(to_balance + amount);
    }

    // --- View Functions ---

    #[external("public")]
    #[view]
    fn balance_of_public(owner: AztecAddress) -> pub Field {
        self.storage.public_balances.at(owner).read()
    }

    #[external("public")]
    #[view]
    fn total_supply() -> pub Field {
        self.storage.total_supply.read()
    }

    #[external("public")]
    #[view]
    fn get_admin() -> pub AztecAddress {
        self.storage.admin.read()
    }

    #[external("public")]
    #[view]
    fn get_minter() -> pub AztecAddress {
        self.storage.minter.read()
    }
}

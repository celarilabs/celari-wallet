import XCTest
@testable import CelariWallet

final class CelariWalletTests: XCTestCase {
    func testAccountShortAddress() {
        let account = Account(address: "0x1234567890abcdef1234567890abcdef12345678")
        XCTAssertEqual(account.shortAddress, "0x123456...345678")
    }

    func testTokenDefaults() {
        XCTAssertEqual(Token.defaults.count, 3)
        XCTAssertEqual(Token.defaults[0].symbol, "zkUSD")
    }

    func testDemoMode() {
        let store = WalletStore()
        store.enterDemoMode()
        XCTAssertEqual(store.accounts.count, 1)
        XCTAssertEqual(store.accounts[0].type, .demo)
        XCTAssertEqual(store.screen, .dashboard)
    }
}

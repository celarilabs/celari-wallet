import Foundation

struct Account: Codable, Identifiable {
    let id: UUID
    var address: String
    var credentialId: String
    var publicKeyX: String
    var publicKeyY: String
    var type: AccountType
    var label: String
    var deployed: Bool
    var salt: String?
    var secretKey: String?
    var privateKeyPkcs8: String?
    var network: String?
    var txHash: String?
    var blockNumber: String?
    var createdAt: Date

    enum AccountType: String, Codable {
        case passkey
        case demo
    }

    init(
        id: UUID = UUID(),
        address: String = "",
        credentialId: String = "",
        publicKeyX: String = "",
        publicKeyY: String = "",
        type: AccountType = .passkey,
        label: String = "Account 1",
        deployed: Bool = false,
        salt: String? = nil,
        secretKey: String? = nil,
        privateKeyPkcs8: String? = nil,
        network: String? = nil,
        txHash: String? = nil,
        blockNumber: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.address = address
        self.credentialId = credentialId
        self.publicKeyX = publicKeyX
        self.publicKeyY = publicKeyY
        self.type = type
        self.label = label
        self.deployed = deployed
        self.salt = salt
        self.secretKey = secretKey
        self.privateKeyPkcs8 = privateKeyPkcs8
        self.network = network
        self.txHash = txHash
        self.blockNumber = blockNumber
        self.createdAt = createdAt
    }

    var shortAddress: String {
        guard address.count > 14 else { return address }
        return "\(address.prefix(8))...\(address.suffix(6))"
    }

    var chipAddress: String {
        guard address.count > 10 else { return "New" }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
}

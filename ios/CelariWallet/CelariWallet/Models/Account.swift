import Foundation

struct Account: Codable, Identifiable {
    static let currentSchemaVersion = 2

    let id: UUID
    var address: String
    var credentialId: String
    var publicKeyX: String
    var publicKeyY: String
    var type: AccountType
    var label: String
    var deployed: Bool
    var salt: String?
    var network: String?
    var txHash: String?
    var blockNumber: String?
    var createdAt: Date
    var schemaVersion: Int

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
        network: String? = nil,
        txHash: String? = nil,
        blockNumber: String? = nil,
        createdAt: Date = Date(),
        schemaVersion: Int = Account.currentSchemaVersion
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
        self.network = network
        self.txHash = txHash
        self.blockNumber = blockNumber
        self.createdAt = createdAt
        self.schemaVersion = schemaVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        address = try container.decode(String.self, forKey: .address)
        credentialId = try container.decode(String.self, forKey: .credentialId)
        publicKeyX = try container.decode(String.self, forKey: .publicKeyX)
        publicKeyY = try container.decode(String.self, forKey: .publicKeyY)
        type = try container.decode(AccountType.self, forKey: .type)
        label = try container.decode(String.self, forKey: .label)
        deployed = try container.decode(Bool.self, forKey: .deployed)
        salt = try container.decodeIfPresent(String.self, forKey: .salt)
        network = try container.decodeIfPresent(String.self, forKey: .network)
        txHash = try container.decodeIfPresent(String.self, forKey: .txHash)
        blockNumber = try container.decodeIfPresent(String.self, forKey: .blockNumber)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        // Backwards-compatible: old accounts without schemaVersion default to 1
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }

    var shortAddress: String {
        if address.hasPrefix("pending_") { return "Pending..." }
        guard address.count > 14 else { return address }
        return "\(address.prefix(8))...\(address.suffix(6))"
    }

    var chipAddress: String {
        if address.hasPrefix("pending_") { return "Pending" }
        guard address.count > 10 else { return "New" }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
}

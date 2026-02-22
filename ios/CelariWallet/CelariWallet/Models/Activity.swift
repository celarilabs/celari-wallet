import Foundation

struct Activity: Codable, Identifiable {
    let id: UUID
    var type: ActivityType
    var label: String
    var amount: String
    var time: String
    var isPrivate: Bool
    var txHash: String?

    enum ActivityType: String, Codable {
        case send
        case receive
    }

    init(
        id: UUID = UUID(),
        type: ActivityType,
        label: String,
        amount: String,
        time: String = "Now",
        isPrivate: Bool = true,
        txHash: String? = nil
    ) {
        self.id = id
        self.type = type
        self.label = label
        self.amount = amount
        self.time = time
        self.isPrivate = isPrivate
        self.txHash = txHash
    }
}

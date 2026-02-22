import Foundation

struct NFTItem: Codable, Identifiable {
    var id: String { "\(contractAddress)_\(tokenId)" }
    var contractAddress: String
    var contractName: String
    var tokenId: String
    var visibility: String  // "private" or "public"

    var isPrivate: Bool { visibility == "private" }
}

struct NFTContract: Codable, Identifiable {
    var id: String { address }
    var address: String
    var name: String
    var symbol: String
}

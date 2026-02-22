import Foundation

struct WCSession: Codable, Identifiable {
    var id: String { topic }
    var topic: String
    var peerName: String
    var peerUrl: String
    var chains: [String]
    var expiry: Int?
}

struct WCProposal: Codable {
    var id: Int
    var peerName: String
    var peerUrl: String
}

import Foundation

struct Token: Codable, Identifiable {
    var id: String { symbol }
    var name: String
    var symbol: String
    var balance: String
    var publicBalance: String?
    var privateBalance: String?
    var value: String
    var icon: String
    var color: String
    var contractAddress: String?
    var decimals: Int?
    var isCustom: Bool

    static let defaults: [Token] = [
        Token(name: "Celari USD", symbol: "zkUSD", balance: "0.00", value: "$0.00",
              icon: "C", color: "#C87941", isCustom: false),
        Token(name: "Wrapped ETH", symbol: "zkETH", balance: "0.000", value: "$0.00",
              icon: "E", color: "#8B2D3A", isCustom: false),
        Token(name: "Privacy Token", symbol: "ZKP", balance: "0", value: "$0.00",
              icon: "Z", color: "#9A7B5B", isCustom: false),
    ]
}

struct CustomToken: Codable, Identifiable {
    var id: String { contractAddress }
    var contractAddress: String
    var name: String
    var symbol: String
    var decimals: Int
}

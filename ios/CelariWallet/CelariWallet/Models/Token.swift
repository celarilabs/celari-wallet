import Foundation

struct Token: Codable, Identifiable {
    // Use contractAddress+symbol as unique ID to avoid SwiftUI list collisions (4.11 audit fix)
    var id: String { (contractAddress ?? "") + ":" + symbol }
    var name: String
    var symbol: String

    /// AIP-20: separate private and public balances
    var privateBalance: String = "0"
    var publicBalance: String = "0"

    /// Total balance computed from private + public (AIP-20)
    var balance: String {
        get {
            let priv = Double(privateBalance) ?? 0
            let pub = Double(publicBalance) ?? 0
            let total = priv + pub
            if total == 0 { return "0" }
            // Use appropriate decimal precision
            if total < 0.001 && total > 0 { return String(format: "%.6f", total) }
            if total == total.rounded() { return String(format: "%.0f", total) }
            return String(format: "%.3f", total)
        }
        set {
            // Allow direct setting for backward compatibility (e.g. from server response)
            // If private/public aren't set, put the full balance into private by default
            if privateBalance == "0" && publicBalance == "0" && newValue != "0" {
                privateBalance = newValue
            }
        }
    }

    var value: String
    var icon: String
    var color: String
    var contractAddress: String?
    var decimals: Int?
    var isCustom: Bool

    /// Whether this token has a meaningful private/public breakdown to display
    var hasBalanceBreakdown: Bool {
        let priv = Double(privateBalance) ?? 0
        let pub = Double(publicBalance) ?? 0
        return priv > 0 || pub > 0
    }

    // Custom Codable to handle balance as computed property
    enum CodingKeys: String, CodingKey {
        case name, symbol, privateBalance, publicBalance, value, icon, color
        case contractAddress, decimals, isCustom
        // Legacy key for backward compatibility
        case balance
    }

    init(name: String, symbol: String, balance: String = "0",
         publicBalance: String = "0", privateBalance: String = "0",
         value: String, icon: String, color: String,
         contractAddress: String? = nil, decimals: Int? = nil, isCustom: Bool) {
        self.name = name
        self.symbol = symbol
        self.privateBalance = privateBalance
        self.publicBalance = publicBalance
        self.value = value
        self.icon = icon
        self.color = color
        self.contractAddress = contractAddress
        self.decimals = decimals
        self.isCustom = isCustom
        // If explicit balance provided but private/public are zero, store in private
        if balance != "0" && privateBalance == "0" && publicBalance == "0" {
            self.privateBalance = balance
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        symbol = try c.decode(String.self, forKey: .symbol)
        privateBalance = try c.decodeIfPresent(String.self, forKey: .privateBalance) ?? "0"
        publicBalance = try c.decodeIfPresent(String.self, forKey: .publicBalance) ?? "0"
        value = try c.decode(String.self, forKey: .value)
        icon = try c.decode(String.self, forKey: .icon)
        color = try c.decode(String.self, forKey: .color)
        contractAddress = try c.decodeIfPresent(String.self, forKey: .contractAddress)
        decimals = try c.decodeIfPresent(Int.self, forKey: .decimals)
        isCustom = try c.decode(Bool.self, forKey: .isCustom)
        // Backward compat: if legacy balance exists but private/public are zero, use it
        if let legacyBalance = try c.decodeIfPresent(String.self, forKey: .balance),
           privateBalance == "0" && publicBalance == "0" && legacyBalance != "0" {
            privateBalance = legacyBalance
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(privateBalance, forKey: .privateBalance)
        try c.encode(publicBalance, forKey: .publicBalance)
        try c.encode(balance, forKey: .balance)
        try c.encode(value, forKey: .value)
        try c.encode(icon, forKey: .icon)
        try c.encode(color, forKey: .color)
        try c.encodeIfPresent(contractAddress, forKey: .contractAddress)
        try c.encodeIfPresent(decimals, forKey: .decimals)
        try c.encode(isCustom, forKey: .isCustom)
    }

    static let defaults: [Token] = [
        Token(name: "Celari USD", symbol: "zkUSD", value: "$0.00",
              icon: "C", color: "#C87941", isCustom: false),
        Token(name: "Wrapped ETH", symbol: "zkETH", value: "$0.00",
              icon: "E", color: "#8B2D3A", isCustom: false),
        Token(name: "Privacy Token", symbol: "ZKP", value: "$0.00",
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

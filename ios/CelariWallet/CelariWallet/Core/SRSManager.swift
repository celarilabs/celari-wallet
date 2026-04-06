import Foundation
import os

private let srsLog = Logger(subsystem: "com.celari.wallet", category: "SRSManager")

/// Manages download and caching of Structured Reference String (SRS) files
/// required for zero-knowledge proof generation.
///
/// Two SRS types are needed:
/// - **BN254**: For standard UltraHonk proving and the mega proof component of IVC
/// - **Grumpkin**: For recursive verification (ECCVM, IPA) in chonk/IVC proving
@Observable
final class SRSManager {
    static let shared = SRSManager()

    private(set) var isDownloading = false
    private(set) var downloadProgress: Double = 0
    private(set) var bn254Ready = false
    private(set) var grumpkinReady = false

    var isChonkReady: Bool { bn254Ready && grumpkinReady }

    // MARK: - Constants

    /// BN254 G1 point size: 64 bytes per point
    private static let pointSize = 64
    /// Default BN254 SRS size for iOS: 2^18 = 262144 points (~16.7MB)
    static let defaultBN254Size: UInt32 = 262_144
    /// Fixed Grumpkin SRS size: 2^16 + 1 = 65537 points (~4.2MB)
    static let grumpkinSize: UInt32 = 65_537

    /// Remote SRS endpoints
    private static let bn254G1URL = "https://crs.aztec-cdn.foundation/g1.dat"
    private static let bn254G2Data: [UInt8] = [
        1, 24, 196, 213, 184, 55, 188, 194, 188, 137, 181, 179, 152, 181, 151, 78,
        159, 89, 68, 7, 59, 50, 7, 139, 126, 35, 31, 236, 147, 136, 131, 176,
        38, 14, 1, 178, 81, 246, 241, 199, 231, 255, 78, 88, 7, 145, 222, 232,
        234, 81, 216, 122, 53, 142, 3, 139, 78, 254, 48, 250, 192, 147, 131, 193,
        34, 254, 189, 163, 192, 192, 99, 42, 86, 71, 91, 66, 20, 229, 97, 94,
        17, 230, 221, 63, 150, 230, 206, 162, 133, 74, 135, 212, 218, 204, 94, 85,
        4, 252, 99, 105, 247, 17, 15, 227, 210, 81, 86, 193, 187, 154, 114, 133,
        156, 242, 160, 70, 65, 249, 155, 164, 238, 65, 60, 128, 218, 106, 95, 228,
    ]
    private static let grumpkinG1URL = "https://crs.aztec-cdn.foundation/grumpkin_g1.dat"

    private init() {
        // Check files exist AND have minimum expected size
        let bn254MinSize = Int(Self.defaultBN254Size + 1) * Self.pointSize
        let grumpkinMinSize = Int(Self.grumpkinSize + 1) * Self.pointSize
        let bn254Size = (try? FileManager.default.attributesOfItem(atPath: bn254G1Path.path)[.size] as? Int) ?? 0
        let grumpkinSize = (try? FileManager.default.attributesOfItem(atPath: grumpkinG1Path.path)[.size] as? Int) ?? 0
        bn254Ready = bn254Size >= bn254MinSize
        grumpkinReady = grumpkinSize >= grumpkinMinSize
    }

    // MARK: - File Paths

    static var srsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("celari/srs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var bn254G1Path: URL { Self.srsDirectory.appendingPathComponent("bn254_g1.dat") }
    var bn254G2Path: URL { Self.srsDirectory.appendingPathComponent("bn254_g2.dat") }
    var grumpkinG1Path: URL { Self.srsDirectory.appendingPathComponent("grumpkin_g1.dat") }

    // MARK: - Download & Cache

    /// Ensure both BN254 and Grumpkin SRS files are cached locally.
    /// Downloads missing files from Aztec's S3 endpoints.
    func ensureAllSRS() async throws {
        try await ensureBN254SRS()
        try await ensureGrumpkinSRS()
    }

    /// Ensure BN254 SRS is cached. Downloads if missing.
    func ensureBN254SRS(numPoints: UInt32 = defaultBN254Size) async throws {
        if bn254Ready { return }

        isDownloading = true
        defer { isDownloading = false }

        srsLog.notice("Downloading BN254 SRS (\(numPoints) points)...")

        // Download G1 points (g1.dat is raw G1 points, no header)
        // noir_rs needs subgroup_size + 1 points, so download extra
        let requiredBytes = Int(numPoints + 1) * Self.pointSize
        let g1Data = try await downloadWithProgress(
            from: Self.bn254G1URL,
            label: "BN254 G1",
            maxBytes: requiredBytes
        )

        guard g1Data.count >= requiredBytes else {
            throw SRSError.downloadTooSmall(expected: requiredBytes, got: g1Data.count)
        }
        let g1Points = g1Data.prefix(requiredBytes)

        try g1Points.write(to: bn254G1Path)
        try Data(Self.bn254G2Data).write(to: bn254G2Path)

        bn254Ready = true
        srsLog.notice("BN254 SRS cached: \(g1Points.count) bytes (\(numPoints) points)")
    }

    /// Ensure Grumpkin SRS is cached. Downloads if missing.
    func ensureGrumpkinSRS(numPoints: UInt32 = grumpkinSize) async throws {
        if grumpkinReady { return }

        isDownloading = true
        defer { isDownloading = false }

        srsLog.notice("Downloading Grumpkin SRS (\(numPoints) points)...")

        // Download extra point for safety margin
        let requiredBytes = Int(numPoints + 1) * Self.pointSize
        let g1Data = try await downloadWithProgress(
            from: Self.grumpkinG1URL,
            label: "Grumpkin G1",
            maxBytes: requiredBytes
        )

        guard g1Data.count >= requiredBytes else {
            throw SRSError.downloadTooSmall(expected: requiredBytes, got: g1Data.count)
        }
        let g1Points = g1Data.prefix(requiredBytes)

        try g1Points.write(to: grumpkinG1Path)

        grumpkinReady = true
        srsLog.notice("Grumpkin SRS cached: \(g1Points.count) bytes (\(numPoints) points)")
    }

    /// Delete all cached SRS files.
    func clearCache() throws {
        try? FileManager.default.removeItem(at: bn254G1Path)
        try? FileManager.default.removeItem(at: bn254G2Path)
        try? FileManager.default.removeItem(at: grumpkinG1Path)
        bn254Ready = false
        grumpkinReady = false
        srsLog.notice("SRS cache cleared")
    }

    /// Total size of cached SRS files in bytes.
    var cacheSize: Int {
        let paths = [bn254G1Path, bn254G2Path, grumpkinG1Path]
        return paths.reduce(0) { total, path in
            total + ((try? FileManager.default.attributesOfItem(atPath: path.path)[.size] as? Int) ?? 0)
        }
    }

    // MARK: - Download Helper

    private func downloadWithProgress(from urlString: String, label: String, maxBytes: Int) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw SRSError.invalidURL(urlString)
        }

        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
        let totalBytes = Int(response.expectedContentLength)
        let effectiveTotal = totalBytes > 0 ? min(totalBytes, maxBytes) : maxBytes

        var data = Data()
        data.reserveCapacity(min(effectiveTotal, maxBytes))

        for try await byte in asyncBytes {
            data.append(byte)
            if data.count >= maxBytes { break }

            if data.count % (1024 * 256) == 0 { // Update every 256KB
                downloadProgress = Double(data.count) / Double(effectiveTotal)
            }
        }

        downloadProgress = 1.0
        srsLog.notice("\(label) downloaded: \(data.count) bytes")
        return data
    }
}

enum SRSError: LocalizedError {
    case downloadTooSmall(expected: Int, got: Int)
    case invalidURL(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadTooSmall(let expected, let got):
            return "SRS download too small: expected \(expected) bytes, got \(got)"
        case .invalidURL(let url):
            return "Invalid SRS URL: \(url)"
        case .downloadFailed(let msg):
            return "SRS download failed: \(msg)"
        }
    }
}

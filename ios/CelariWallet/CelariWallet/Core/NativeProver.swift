import Foundation
import Swoirenberg
import SwoirCore

// NATIVE PROVER STATUS
// ====================
// Current: DISABLED (WASM fallback active)
// Reason: Swoirenberg XCFramework chonk_prove crashes on some circuits
// Decision gate: End of Week 4 (approx. 2026-04-27)
//   - If stable on iPhone 13+: enable native proving, keep WASM as fallback
//   - If unstable: stay on WASM, track CHONK prover for future integration
// To test: Set NativeProver.isEnabled = true and run proof benchmark

/// Native Barretenberg prover using Swoirenberg XCFramework.
/// Provides 8-12x speedup over WASM proving in WKWebView.
/// Supports both single-circuit UltraHonk and multi-circuit Chonk/IVC proving.
@Observable
final class NativeProver {
    static let shared = NativeProver()

    /// Returns true if native proving is available and stable.
    /// Set to false to force WASM fallback.
    static let isEnabled: Bool = false // Decision gate: Week 4 — set to true after Swoirenberg stabilizes

    private(set) var isReady = false
    private(set) var isChonkReady = false
    private(set) var lastProveTime: TimeInterval?
    private(set) var lastChonkProveTime: TimeInterval?

    private init() {}

    // MARK: - SRS Setup

    /// Initialize BN254 SRS (Structured Reference String) for a given circuit size.
    /// Must be called before proving. Downloads SRS points if not cached.
    func setupSRS(circuitSize: UInt32) throws {
        let srsPath = Self.srsDirectory.path
        let _ = try Swoirenberg.setup_srs(circuit_size: circuitSize, srs_path: srsPath)
        isReady = true
    }

    /// Initialize SRS from ACIR bytecode (auto-detects required size).
    func setupSRS(fromBytecode bytecode: Data) throws {
        let srsPath = Self.srsDirectory.path
        let _ = try Swoirenberg.setup_srs_from_bytecode(bytecode: bytecode, srs_path: srsPath)
        isReady = true
    }

    /// Initialize Grumpkin curve SRS for chonk/IVC proving.
    /// Required for recursive verification components (ECCVM, IPA).
    /// Default: 65537 points (~4.2MB).
    func setupGrumpkinSRS(numPoints: UInt32 = 65537) throws {
        let srsPath = Self.srsDirectory.path
        let _ = try Swoirenberg.setup_grumpkin_srs(num_points: numPoints, srs_path: srsPath)
    }

    /// Initialize both BN254 and Grumpkin SRS for full chonk proving.
    /// Downloads raw SRS bytes via SRSManager, then passes directly to Rust.
    /// No file path needed — avoids noir_rs LocalSrs format issues.
    func setupForChonk(bn254Size: UInt32 = 262144) async throws {
        // Download SRS files if not cached
        try await SRSManager.shared.ensureAllSRS()

        // Read raw G1 bytes and pass directly to Rust
        let bn254G1 = try Data(contentsOf: SRSManager.shared.bn254G1Path)
        // Use the known constant, not file size calculation
        try Swoirenberg.setup_srs_raw(g1_data: bn254G1, num_points: bn254Size + 1)
        isReady = true

        let grumpkinG1 = try Data(contentsOf: SRSManager.shared.grumpkinG1Path)
        try Swoirenberg.setup_grumpkin_srs_raw(g1_data: grumpkinG1, num_points: SRSManager.grumpkinSize)
        isChonkReady = true
    }

    // MARK: - Single-Circuit Proving (UltraHonk)

    /// Generate an UltraHonk proof for the given circuit bytecode and witness.
    func prove(bytecode: Data, witnessMap: [String], proofType: String = "ultra_honk") throws -> Data {
        guard isReady else {
            throw NativeProverError.srsNotInitialized
        }

        let vkey = try Swoirenberg.get_verification_key(
            bytecode: bytecode,
            proof_type: proofType,
            low_memory_mode: false,
            storage_cap: nil
        )

        let start = CFAbsoluteTimeGetCurrent()
        let proof = try Swoirenberg.prove(
            bytecode: bytecode,
            witnessMap: witnessMap,
            proof_type: proofType,
            vkey: vkey,
            low_memory_mode: false,
            storage_cap: nil
        )
        lastProveTime = CFAbsoluteTimeGetCurrent() - start

        return proof
    }

    /// Verify a proof against the circuit bytecode.
    func verify(proof: Data, bytecode: Data, proofType: String = "ultra_honk") throws -> Bool {
        let vkey = try Swoirenberg.get_verification_key(
            bytecode: bytecode,
            proof_type: proofType,
            low_memory_mode: false,
            storage_cap: nil
        )
        return try Swoirenberg.verify(proof: proof, vkey: vkey, proof_type: proofType)
    }

    /// Execute the circuit (compute witness) without generating a proof.
    func execute(bytecode: Data, witnessMap: [String]) throws -> [String] {
        return try Swoirenberg.execute(bytecode: bytecode, witnessMap: witnessMap)
    }

    // MARK: - Multi-Circuit Chonk/IVC Proving

    /// Initialize a chonk proving session for N circuits.
    func chonkStart(numCircuits: UInt32) throws {
        guard isChonkReady else {
            throw NativeProverError.chonkNotReady
        }
        guard try Swoirenberg.chonk_start(num_circuits: numCircuits) else {
            throw NativeProverError.chonkSessionFailed("chonk_start returned false")
        }
    }

    /// Load a circuit into the current chonk session.
    func chonkLoad(name: String, bytecode: Data, verificationKey: Data) throws {
        guard try Swoirenberg.chonk_load(
            name: name,
            bytecode: bytecode,
            verification_key: verificationKey
        ) else {
            throw NativeProverError.chonkSessionFailed("chonk_load failed for \(name)")
        }
    }

    /// Accumulate a witness for the most recently loaded circuit.
    func chonkAccumulate(witness: Data) throws {
        guard try Swoirenberg.chonk_accumulate(witness: witness) else {
            throw NativeProverError.chonkSessionFailed("chonk_accumulate failed")
        }
    }

    /// Generate IVC proof from all accumulated circuits.
    /// Returns msgpack-serialized ChonkProof bytes.
    func chonkProve() throws -> Data {
        let start = CFAbsoluteTimeGetCurrent()
        do {
            guard let proof = try Swoirenberg.chonk_prove() else {
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                throw NativeProverError.chonkSessionFailed("chonk_prove returned nil after \(String(format: "%.2f", elapsed))s")
            }
            lastChonkProveTime = CFAbsoluteTimeGetCurrent() - start
            return proof
        } catch let error as NativeProverError {
            throw error
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            throw NativeProverError.chonkSessionFailed("chonk_prove crashed after \(String(format: "%.2f", elapsed))s: \(error.localizedDescription)")
        }
    }

    /// Verify a chonk proof against a verification key.
    func chonkVerify(proof: Data, verificationKey: Data) throws -> Bool {
        return try Swoirenberg.chonk_verify(proof: proof, vk: verificationKey)
    }

    /// Compute chonk verification key for a circuit.
    func chonkComputeVK(bytecode: Data) throws -> Data {
        guard let vk = try Swoirenberg.chonk_compute_vk(bytecode: bytecode) else {
            throw NativeProverError.chonkSessionFailed("chonk_compute_vk returned nil")
        }
        return vk
    }

    /// Destroy the current chonk session and free resources.
    func chonkDestroy() throws {
        let _ = try Swoirenberg.chonk_destroy()
    }

    /// High-level: prove a complete transaction in one call.
    /// Each step = (name, bytecode, witness, vkey) for a kernel circuit.
    func proveTransaction(steps: [(name: String, bytecode: Data, witness: Data, vkey: Data)]) throws -> Data {
        guard isChonkReady else {
            throw NativeProverError.chonkNotReady
        }

        let names = steps.map { $0.name }
        let bytecodes = steps.map { $0.bytecode }
        let witnesses = steps.map { $0.witness }
        let vkeys = steps.map { $0.vkey }

        let start = CFAbsoluteTimeGetCurrent()
        guard let proof = try Swoirenberg.chonk_prove_transaction(
            names: names,
            bytecodes: bytecodes,
            witnesses: witnesses,
            vkeys: vkeys,
            low_memory_mode: false,
            storage_cap: 0
        ) else {
            throw NativeProverError.chonkSessionFailed("chonk_prove_transaction returned nil")
        }
        lastChonkProveTime = CFAbsoluteTimeGetCurrent() - start
        return proof
    }

    // MARK: - SRS Storage

    private static var srsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("celari/srs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

enum NativeProverError: LocalizedError {
    case srsNotInitialized
    case chonkNotReady
    case invalidBytecode
    case provingFailed(String)
    case chonkSessionFailed(String)

    var errorDescription: String? {
        switch self {
        case .srsNotInitialized: return "SRS not initialized. Call setupSRS first."
        case .chonkNotReady: return "Chonk SRS not initialized. Call setupForChonk first."
        case .invalidBytecode: return "Invalid ACIR bytecode"
        case .provingFailed(let msg): return "Proving failed: \(msg)"
        case .chonkSessionFailed(let msg): return "Chonk session failed: \(msg)"
        }
    }
}

import Foundation
import os.log
import Swoirenberg
import SwoirCore

private let nativeProverLog = Logger(subsystem: "com.celari.wallet", category: "PXENativeProver")

// MARK: - PXENativeProver

/// Handles all Swoirenberg native prover operations on behalf of the JS layer.
/// Actions are dispatched from PXEBridge's "nativeProver" WKScriptMessage handler
/// and results are returned to JS via `window._nativeProverCallback`.
final class PXENativeProver {
    private weak var messageBus: PXEMessageBus?

    init(messageBus: PXEMessageBus) {
        self.messageBus = messageBus
    }

    // MARK: - Entry Point

    func handleRequest(_ json: [String: Any]) {
        let action = json["action"] as? String ?? ""
        let callbackId = json["callbackId"] as? String ?? ""

        nativeProverLog.notice("[NativeProver] action=\(action, privacy: .public), cbId=\(callbackId, privacy: .public)")

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                var result: [String: Any] = [:]

                switch action {
                case "setup_srs":
                    let circuitSize = json["circuitSize"] as? UInt32 ?? 500
                    let numPoints = try Swoirenberg.setup_srs(circuit_size: circuitSize, srs_path: nil)
                    result["numPoints"] = numPoints

                case "setup_srs_from_bytecode":
                    guard let b64 = json["bytecode"] as? String,
                          let bytecode = Data(base64Encoded: b64) else {
                        throw NativeProverError.invalidBytecode
                    }
                    let numPoints = try Swoirenberg.setup_srs_from_bytecode(bytecode: bytecode, srs_path: nil)
                    result["numPoints"] = numPoints

                case "execute":
                    guard let b64 = json["bytecode"] as? String,
                          let bytecode = Data(base64Encoded: b64),
                          let witnessMap = json["witnessMap"] as? [String] else {
                        throw NativeProverError.invalidBytecode
                    }
                    let solvedWitness = try Swoirenberg.execute(bytecode: bytecode, witnessMap: witnessMap)
                    result["witness"] = solvedWitness

                case "prove":
                    guard let b64 = json["bytecode"] as? String,
                          let bytecode = Data(base64Encoded: b64),
                          let witnessMap = json["witnessMap"] as? [String] else {
                        throw NativeProverError.invalidBytecode
                    }
                    let proofType = json["proofType"] as? String ?? "ultra_honk"
                    let vkey = try Swoirenberg.get_verification_key(
                        bytecode: bytecode, proof_type: proofType,
                        low_memory_mode: false, storage_cap: nil
                    )
                    let start = CFAbsoluteTimeGetCurrent()
                    let proof = try Swoirenberg.prove(
                        bytecode: bytecode, witnessMap: witnessMap,
                        proof_type: proofType, vkey: vkey,
                        low_memory_mode: false, storage_cap: nil
                    )
                    let elapsed = CFAbsoluteTimeGetCurrent() - start
                    result["proof"] = proof.map { String(format: "%02x", $0) }.joined()
                    result["proofSize"] = proof.count
                    result["proveTimeMs"] = Int(elapsed * 1000)
                    result["vkey"] = vkey.map { String(format: "%02x", $0) }.joined()

                case "verify":
                    guard let proofHex = json["proof"] as? String,
                          let vkeyHex = json["vkey"] as? String else {
                        throw NativeProverError.invalidBytecode
                    }
                    let proofType = json["proofType"] as? String ?? "ultra_honk"
                    let proof = Data(hexString: proofHex)
                    let vkey = Data(hexString: vkeyHex)
                    let valid = try Swoirenberg.verify(proof: proof, vkey: vkey, proof_type: proofType)
                    result["verified"] = valid

                case "get_vkey":
                    guard let b64 = json["bytecode"] as? String,
                          let bytecode = Data(base64Encoded: b64) else {
                        throw NativeProverError.invalidBytecode
                    }
                    let proofType = json["proofType"] as? String ?? "ultra_honk"
                    let vkey = try Swoirenberg.get_verification_key(
                        bytecode: bytecode, proof_type: proofType,
                        low_memory_mode: false, storage_cap: nil
                    )
                    result["vkey"] = vkey.map { String(format: "%02x", $0) }.joined()
                    result["vkeySize"] = vkey.count

                // ── Chonk/IVC Pipeline ──

                case "setup_grumpkin_srs":
                    let numPoints = json["numPoints"] as? UInt32 ?? 65537
                    try NativeProver.shared.setupGrumpkinSRS(numPoints: numPoints)
                    result["success"] = true

                case "setup_for_chonk":
                    let bn254Size = json["bn254Size"] as? UInt32 ?? 262144
                    try await NativeProver.shared.setupForChonk(bn254Size: bn254Size)
                    result["success"] = true

                case "chonk_start":
                    let numCircuits = json["numCircuits"] as? UInt32 ?? 0
                    try NativeProver.shared.chonkStart(numCircuits: numCircuits)
                    result["success"] = true

                case "chonk_load":
                    guard let name = json["name"] as? String,
                          let b64Bytecode = json["bytecode"] as? String,
                          let bytecode = Data(base64Encoded: b64Bytecode),
                          let b64Vkey = json["vkey"] as? String,
                          let vkey = Data(base64Encoded: b64Vkey) else {
                        throw NativeProverError.invalidBytecode
                    }
                    try NativeProver.shared.chonkLoad(name: name, bytecode: bytecode, verificationKey: vkey)
                    result["success"] = true

                case "chonk_accumulate":
                    guard let b64Witness = json["witness"] as? String,
                          let witness = Data(base64Encoded: b64Witness) else {
                        throw NativeProverError.invalidBytecode
                    }
                    try NativeProver.shared.chonkAccumulate(witness: witness)
                    result["success"] = true

                case "chonk_prove":
                    let start = CFAbsoluteTimeGetCurrent()
                    let proof = try NativeProver.shared.chonkProve()
                    let elapsed = CFAbsoluteTimeGetCurrent() - start
                    result["proof"] = proof.base64EncodedString()
                    result["proofSize"] = proof.count
                    result["proveTimeMs"] = Int(elapsed * 1000)

                case "chonk_verify":
                    guard let b64Proof = json["proof"] as? String,
                          let proof = Data(base64Encoded: b64Proof),
                          let b64Vkey = json["vkey"] as? String,
                          let vkey = Data(base64Encoded: b64Vkey) else {
                        throw NativeProverError.invalidBytecode
                    }
                    let valid = try NativeProver.shared.chonkVerify(proof: proof, verificationKey: vkey)
                    result["verified"] = valid

                case "chonk_compute_vk":
                    guard let b64Bytecode = json["bytecode"] as? String,
                          let bytecode = Data(base64Encoded: b64Bytecode) else {
                        throw NativeProverError.invalidBytecode
                    }
                    let vk = try NativeProver.shared.chonkComputeVK(bytecode: bytecode)
                    result["vkey"] = vk.base64EncodedString()
                    result["vkeySize"] = vk.count

                case "chonk_destroy":
                    try NativeProver.shared.chonkDestroy()
                    result["success"] = true

                case "chonk_prove_transaction":
                    guard let names = json["names"] as? [String],
                          let b64Bytecodes = json["bytecodes"] as? [String],
                          let b64Witnesses = json["witnesses"] as? [String],
                          let b64Vkeys = json["vkeys"] as? [String] else {
                        throw NativeProverError.invalidBytecode
                    }
                    let steps: [(name: String, bytecode: Data, witness: Data, vkey: Data)] = try zip(
                        zip(names, b64Bytecodes),
                        zip(b64Witnesses, b64Vkeys)
                    ).map { pair in
                        guard let bc = Data(base64Encoded: pair.0.1),
                              let w = Data(base64Encoded: pair.1.0),
                              let vk = Data(base64Encoded: pair.1.1) else {
                            throw NativeProverError.invalidBytecode
                        }
                        return (name: pair.0.0, bytecode: bc, witness: w, vkey: vk)
                    }
                    let start = CFAbsoluteTimeGetCurrent()
                    let proof = try NativeProver.shared.proveTransaction(steps: steps)
                    let elapsed = CFAbsoluteTimeGetCurrent() - start
                    result["proof"] = proof.base64EncodedString()
                    result["proofSize"] = proof.count
                    result["proveTimeMs"] = Int(elapsed * 1000)

                default:
                    throw NativeProverError.provingFailed("Unknown action: \(action)")
                }

                await self.deliverCallback(callbackId, result: result)
            } catch {
                nativeProverLog.error("[NativeProver] \(action, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                await self.deliverCallback(callbackId, result: ["error": error.localizedDescription])
            }
        }
    }

    // MARK: - Callback Delivery

    @MainActor
    private func deliverCallback(_ callbackId: String, result: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: result),
              let jsonStr = String(data: jsonData, encoding: .utf8) else { return }

        // Escape the JSON string for safe inline embedding into JS source.
        // Using messageBus.evaluateJS() which takes a raw JS string (no structured arguments).
        let escapedCbId = callbackId
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let escapedJson = jsonStr
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        let js = "window._nativeProverCallback('\(escapedCbId)', '\(escapedJson)')"
        Task {
            try? await messageBus?.evaluateJS(js)
        }
    }
}

import SwiftUI
import Swoirenberg
import SwoirCore

struct ProverBenchmarkView: View {
    @Environment(PXEBridge.self) private var pxeBridge
    @State private var status = "Ready"
    @State private var nativeTime: TimeInterval?
    @State private var srsSetupTime: TimeInterval?
    @State private var isRunning = false
    @State private var proofSize: Int?
    @State private var verified: Bool?
    @State private var logs: [String] = []
    @State private var jsBridgeTime: TimeInterval?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 28))
                    .foregroundColor(V2Colors.aztecGreen)
                Text("Native Prover Benchmark")
                    .font(V2Fonts.heading(20))
                    .foregroundColor(V2Colors.textPrimary)
                Text("Swoirenberg (BB ARM64)")
                    .font(V2Fonts.mono(12))
                    .foregroundColor(V2Colors.textTertiary)
            }
            .padding(.top, 20)

            // Results card
            VStack(spacing: 12) {
                resultRow("SRS Setup", value: srsSetupTime.map { formatTime($0) } ?? "—")
                Divider()
                resultRow("Prove Time", value: nativeTime.map { formatTime($0) } ?? "—", highlight: true)
                Divider()
                resultRow("Proof Size", value: proofSize.map { "\($0) bytes" } ?? "—")
                Divider()
                resultRow("Verified", value: verified.map { $0 ? "Yes" : "FAILED" } ?? "—",
                          color: verified == true ? V2Colors.successGreen : (verified == false ? V2Colors.errorRed : nil))
                Divider()
                resultRow("JS Bridge", value: jsBridgeTime.map { formatTime($0) } ?? "—")
            }
            .padding(16)
            .background(V2Colors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(V2Colors.borderPrimary, lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.top, 20)

            // Circuit info
            VStack(spacing: 4) {
                Text("Test Circuit: x * y = z (multiply)")
                    .font(V2Fonts.mono(11))
                    .foregroundColor(V2Colors.textSecondary)
                Text("Noir 1.0.0-beta.19 • UltraHonk")
                    .font(V2Fonts.mono(10))
                    .foregroundColor(V2Colors.textMuted)
            }
            .padding(.top, 12)

            // Run button
            Button {
                runBenchmark()
            } label: {
                HStack(spacing: 8) {
                    if isRunning {
                        ProgressView().tint(V2Colors.textWhite)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(isRunning ? status : "Run Benchmark")
                }
                .font(V2Fonts.bodySemibold(16))
                .foregroundColor(V2Colors.textWhite)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isRunning ? V2Colors.textMuted : V2Colors.aztecDark)
                )
            }
            .disabled(isRunning)
            .padding(.horizontal, 24)
            .padding(.top, 20)

            // JS Bridge test button
            Button {
                testJSBridge()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Test JS → Swift Bridge")
                }
                .font(V2Fonts.bodyMedium(14))
                .foregroundColor(V2Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(V2Colors.bgControl)
                )
            }
            .disabled(isRunning || !pxeBridge.isReady)
            .padding(.horizontal, 24)
            .padding(.top, 8)

            // Copy logs button
            if !logs.isEmpty {
                Button {
                    UIPasteboard.general.string = logs.joined(separator: "\n")
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy Logs")
                    }
                    .font(V2Fonts.mono(12))
                    .foregroundColor(V2Colors.aztecGreen)
                }
                .padding(.top, 8)
            }

            // Log output
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(logs.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(V2Fonts.mono(10))
                            .foregroundColor(V2Colors.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .background(V2Colors.aztecDark.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Spacer()
        }
        .background(V2Colors.bgCanvas)
        .navigationTitle("Prover Benchmark")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resultRow(_ label: String, value: String, highlight: Bool = false, color: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(V2Fonts.body(14))
                .foregroundColor(V2Colors.textSecondary)
            Spacer()
            Text(value)
                .font(highlight ? V2Fonts.mono(16) : V2Fonts.mono(13))
                .foregroundColor(color ?? (highlight ? V2Colors.aztecGreen : V2Colors.textPrimary))
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        if t < 1 { return String(format: "%.0fms", t * 1000) }
        return String(format: "%.2fs", t)
    }

    @MainActor
    private func addLog(_ msg: String) {
        let ts = String(format: "%.3f", CFAbsoluteTimeGetCurrent().truncatingRemainder(dividingBy: 1000))
        let entry = "[\(ts)] \(msg)"
        logs.append(entry)
        NSLog("[NativeProver] %@", msg)
    }

    private func runBenchmark() {
        isRunning = true
        logs = []
        nativeTime = nil
        srsSetupTime = nil
        proofSize = nil
        verified = nil
        status = "Loading..."

        // Step 0: Load circuit — using Swoirenberg's known-good test circuit (multiply: x * y = z)
        addLog("Phase 0: Loading circuit bytecode...")

        // This is the test circuit from Swoirenberg's own test suite (Noir beta.19 compatible)
        let bytecodeBase64 = "H4sIAAAAAAAA/4XMPQ5AMBiA4aqLGNmIE4hITGIUiUHCYPCTshh7g37tYDWYHEDYXaSb0WLXE/DObx6dw7TUedVgoKvX9yUZ0pK0AsRpoO80pAE/DbuIiHRma4+DjdIkM90rHI8OfPmIW234F0JcSZgx9gL3WmBNjQAAAA=="

        guard let bytecode = Data(base64Encoded: bytecodeBase64) else {
            addLog("ERROR: base64 decode failed")
            status = "Failed"
            isRunning = false
            return
        }

        addLog("Bytecode: \(bytecode.count) bytes (gzipped ACIR)")
        addLog("Phase 0 OK ✓")

        // Phase 1: Try execute() — no SRS needed, tests FFI works
        Task {
            addLog("Phase 1: Testing execute(3, 5) → expect 15...")
            status = "Executing circuit..."

            let execResult: Result<[String], Error> = await Task.detached(priority: .userInitiated) {
                try Swoirenberg.execute(bytecode: bytecode, witnessMap: ["3", "5"])
            }.result

            switch execResult {
            case .success(let solvedWitness):
                addLog("Phase 1 OK ✓ — witnesses: \(solvedWitness.count)")
                if solvedWitness.count >= 3 {
                    addLog("  x=\(solvedWitness[0].suffix(4)), y=\(solvedWitness[1].suffix(4)), z=\(solvedWitness[2].suffix(4))")
                }
            case .failure(let error):
                addLog("Phase 1 FAILED: \(error)")
                status = "Failed at execute()"
                isRunning = false
                return
            }

            // Phase 2: SRS setup
            addLog("Phase 2: SRS setup...")
            status = "SRS setup..."

            let srsResult: Result<(UInt32, TimeInterval), Error> = await Task.detached(priority: .userInitiated) {
                let start = CFAbsoluteTimeGetCurrent()
                let points = try Swoirenberg.setup_srs(circuit_size: 500, srs_path: nil)
                return (points, CFAbsoluteTimeGetCurrent() - start)
            }.result

            switch srsResult {
            case .success(let (numPoints, elapsed)):
                addLog("Phase 2 OK ✓ — \(numPoints) points, \(String(format: "%.3fs", elapsed))")
                srsSetupTime = elapsed
            case .failure(let error):
                addLog("Phase 2 FAILED: \(error)")
                status = "Failed at SRS"
                isRunning = false
                return
            }

            // Phase 3: Get vkey
            addLog("Phase 3: Verification key...")
            status = "Getting vkey..."

            let vkeyResult: Result<Data, Error> = await Task.detached(priority: .userInitiated) {
                try Swoirenberg.get_verification_key(
                    bytecode: bytecode, proof_type: "ultra_honk",
                    low_memory_mode: false, storage_cap: nil
                )
            }.result

            let vkey: Data
            switch vkeyResult {
            case .success(let v):
                vkey = v
                addLog("Phase 3 OK ✓ — vkey \(v.count) bytes")
            case .failure(let error):
                addLog("Phase 3 FAILED: \(error)")
                status = "Failed at vkey"
                isRunning = false
                return
            }

            // Phase 4: Prove
            // prove() needs full witness including output: [x, y, z] in hex
            addLog("Phase 4: Proving [0x3, 0x5, 0xf]...")
            status = "Proving..."

            let proveResult: Result<(Data, TimeInterval), Error> = await Task.detached(priority: .userInitiated) {
                let start = CFAbsoluteTimeGetCurrent()
                let proof = try Swoirenberg.prove(
                    bytecode: bytecode, witnessMap: ["0x3", "0x5", "0xf"],
                    proof_type: "ultra_honk", vkey: vkey,
                    low_memory_mode: false, storage_cap: nil
                )
                return (proof, CFAbsoluteTimeGetCurrent() - start)
            }.result

            let proof: Data
            switch proveResult {
            case .success(let (p, elapsed)):
                proof = p
                addLog("Phase 4 OK ✓ — proof \(p.count) bytes in \(String(format: "%.3fs", elapsed))")
                nativeTime = elapsed
                proofSize = p.count
            case .failure(let error):
                addLog("Phase 4 FAILED: \(error)")
                status = "Failed at prove"
                isRunning = false
                return
            }

            // Phase 5: Verify
            addLog("Phase 5: Verifying...")
            status = "Verifying..."

            let verifyResult: Result<Bool, Error> = await Task.detached(priority: .userInitiated) {
                try Swoirenberg.verify(proof: proof, vkey: vkey, proof_type: "ultra_honk")
            }.result

            switch verifyResult {
            case .success(let isValid):
                addLog("Phase 5 OK ✓ — verified: \(isValid)")
                verified = isValid
                status = "Done!"
            case .failure(let error):
                addLog("Phase 5 FAILED: \(error)")
                status = "Failed at verify"
            }

            isRunning = false
        }
    }

    /// Test the full round-trip: JS → postMessage → Swift (Swoirenberg) → callback → JS
    private func testJSBridge() {
        guard pxeBridge.isReady else {
            addLog("JS Bridge: PXE not ready")
            return
        }

        isRunning = true
        jsBridgeTime = nil
        addLog("=== JS Bridge Round-Trip Test ===")

        // The test circuit bytecode (same as benchmark)
        let bytecodeBase64 = "H4sIAAAAAAAA/4XMPQ5AMBiA4aqLGNmIE4hITGIUiUHCYPCTshh7g37tYDWYHEDYXaSb0WLXE/DObx6dw7TUedVgoKvX9yUZ0pK0AsRpoO80pAE/DbuIiHRma4+DjdIkM90rHI8OfPmIW234F0JcSZgx9gL3WmBNjQAAAA=="

        // Call JS which will call window.nativeProver.prove() → Swift → Swoirenberg → callback
        Task {
            addLog("Calling JS: nativeProver.setupSrs(500)...")

            do {
                // Step 1: Setup SRS via JS bridge
                let setupJS = """
                return await window.nativeProver.setupSrs({ circuitSize: 500 });
                """
                let setupResult = try await pxeBridge.evaluateJS(setupJS)
                addLog("SRS via bridge: \(setupResult)")

                // Step 2: Prove via JS bridge
                addLog("Calling JS: nativeProver.prove()...")
                let proveJS = """
                var start = Date.now();
                var result = await window.nativeProver.prove(
                    '\(bytecodeBase64)',
                    ['0x3', '0x5', '0xf'],
                    'ultra_honk'
                );
                result.roundTripMs = Date.now() - start;
                return result;
                """
                let proveResult = try await pxeBridge.evaluateJS(proveJS)
                addLog("Prove via bridge: \(proveResult)")

                if let resultDict = proveResult as? [String: Any] {
                    let proveMs = resultDict["proveTimeMs"] as? Int ?? 0
                    let roundTripMs = resultDict["roundTripMs"] as? Int ?? 0
                    let size = resultDict["proofSize"] as? Int ?? 0
                    addLog("Native prove: \(proveMs)ms, round-trip: \(roundTripMs)ms, proof: \(size) bytes")
                    jsBridgeTime = Double(roundTripMs) / 1000.0
                }

                status = "Bridge OK!"
            } catch {
                addLog("JS Bridge ERROR: \(error.localizedDescription)")
                status = "Bridge failed"
            }

            isRunning = false
        }
    }
}

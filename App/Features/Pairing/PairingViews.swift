@preconcurrency import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

// MARK: - Owner: show code

struct OwnerPairingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var payload: PairingPayload?
    @State private var cloudNote: String?
    @State private var confirmUnpair = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("Pair your dog camera").font(StayFont.display).multilineTextAlignment(.center)
                        Text("On the spare iPhone or iPad, open Stay, choose “This is the dog camera” and scan this code.")
                            .font(StayFont.callout)
                            .foregroundStyle(StayPalette.inkSecondary)
                            .multilineTextAlignment(.center)
                    }
                    Group {
                        if let payload {
                            VStack(spacing: 16) {
                                QRCodeView(text: payload.url.absoluteString)
                                    .frame(width: 230, height: 230)
                                    .padding(18)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                                    .accessibilityLabel(Text("Pairing QR code"))
                                VStack(spacing: 4) {
                                    Text("Or type this code").font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
                                    Text(PairingPayload.displayCode(payload.linkID))
                                        .font(.system(.title, design: .monospaced).weight(.semibold))
                                        .foregroundStyle(StayPalette.ink)
                                        .textSelection(.enabled)
                                }
                            }
                        } else {
                            ProgressView().frame(width: 266, height: 266)
                        }
                    }
                    connectionCard
                    if let cloudNote {
                        Label(cloudNote, systemImage: "icloud.slash")
                            .font(StayFont.caption)
                            .foregroundStyle(StayPalette.inkSecondary)
                            .stayCard(padding: 14, fill: StayPalette.surfaceRaised)
                    }
                    if model.isPaired {
                        Button("Unpair camera", role: .destructive) { confirmUnpair = true }
                            .font(StayFont.headline)
                    }
                }
                .padding(24)
            }
            .stayBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                let result = await model.preparePairing()
                payload = result.payload
                cloudNote = result.cloudError.map { _ in
                    String(localized: "iCloud isn't available, so the camera can pair over Wi-Fi only. Sign in to iCloud on both devices to get alerts away from home.")
                }
            }
            .confirmationDialog("Unpair the dog camera?", isPresented: $confirmUnpair, titleVisibility: .visible) {
                Button("Unpair", role: .destructive) {
                    model.unpair()
                    dismiss()
                }
            } message: {
                Text("You can pair again at any time with a new code.")
            }
        }
    }

    private var connectionCard: some View {
        let nearby = model.nearby.isConnected
        let cloud = model.cameraReachability == .cloud
        return VStack(alignment: .leading, spacing: 12) {
            StatusLine(symbol: "wifi", title: String(localized: "Same Wi-Fi"), detail: nearby ? String(localized: "Connected — live view ready") : String(localized: "Searching…"), isOn: nearby)
            StatusLine(symbol: "icloud.fill", title: String(localized: "iCloud alerts"), detail: cloud ? String(localized: "Camera reachable away from home") : String(localized: "Waiting for the camera to check in"), isOn: cloud)
        }
        .stayCard()
    }
}

struct StatusLine: View {
    var symbol: String
    var title: String
    var detail: String
    var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: symbol, tint: isOn ? StayPalette.calm : StayPalette.inkTertiary, fill: isOn ? StayPalette.calm.opacity(0.14) : StayPalette.surfaceRaised, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(StayFont.bodyEmphasis)
                Text(detail).font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
            }
            Spacer()
            Circle().fill(isOn ? StayPalette.calm : StayPalette.inkTertiary.opacity(0.5)).frame(width: 9, height: 9)
        }
        .accessibilityElement(children: .combine)
    }
}

struct QRCodeView: View {
    var text: String

    var body: some View {
        if let image = Self.make(text) {
            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
        } else {
            Color.clear
        }
    }

    static func make(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Camera: scan code

struct ScanPairingView: View {
    @Environment(AppModel.self) private var model
    var onPaired: () -> Void
    var onSkip: (() -> Void)?

    @State private var typedCode = ""
    @State private var isJoining = false
    @State private var errorText: String?
    @State private var scannerAvailable = AVCaptureDevice.default(for: .video) != nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                OnboardingHeader(
                    eyebrow: String(localized: "Pair with your phone"),
                    title: String(localized: "Scan the code on your phone"),
                    message: String(localized: "On your own phone, open Stay → Settings → Dog camera to show the pairing code.")
                )
                ZStack {
                    if scannerAvailable {
                        QRScannerView { value in
                            guard !isJoining, let url = URL(string: value), let payload = PairingPayload(url: url) else { return }
                            join(payload)
                        }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "camera.metering.unknown").font(.largeTitle)
                            Text("No camera available. Type the code instead.").font(StayFont.callout)
                        }
                        .foregroundStyle(StayPalette.inkSecondary)
                    }
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(StayPalette.apricot, style: StrokeStyle(lineWidth: 3, dash: [14, 10]))
                        .padding(36)
                        .allowsHitTesting(false)
                    if isJoining {
                        ProgressView().controlSize(.large).padding(24).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .frame(height: 300)
                .background(StayPalette.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .accessibilityLabel(Text("QR code scanner"))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Or type the code").font(StayFont.headline)
                    HStack {
                        TextField("XXXX-XXXX", text: $typedCode)
                            .font(.system(.title3, design: .monospaced))
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .padding(14)
                            .background(StayPalette.surface, in: RoundedRectangle(cornerRadius: 14))
                        Button("Pair") {
                            if let payload = PairingPayload(code: typedCode) { join(payload) } else {
                                errorText = String(localized: "That code doesn't look right. It has 8 letters and numbers.")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(typedCode.filter { $0.isLetter || $0.isNumber }.count < 8 || isJoining)
                    }
                    Text("A typed code pairs over Wi-Fi, or over iCloud when both devices use the same Apple Account.")
                        .font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
                }
                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(StayFont.callout)
                        .foregroundStyle(StayPalette.alert)
                }
                if let onSkip {
                    Button("Pair later", action: onSkip)
                        .font(StayFont.headline)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
        .stayBackground()
    }

    private func join(_ payload: PairingPayload) {
        isJoining = true
        errorText = nil
        Task {
            do {
                try await model.joinPairing(payload)
                Haptics.success()
                onPaired()
            } catch {
                errorText = error.localizedDescription
            }
            isJoining = false
        }
    }
}

/// Opened from a stay://pair link.
struct JoinPairingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var payload: PairingPayload
    @State private var state: Phase = .idle

    enum Phase: Equatable { case idle, joining, done, failed(String) }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            IconBadge(symbol: "link", size: 80)
            Text("Pair as the dog camera?").font(StayFont.display).multilineTextAlignment(.center)
            Text("This device will watch and listen for your dog and send alerts to \(payload.ownerName.isEmpty ? String(localized: "your phone") : payload.ownerName).")
                .font(StayFont.callout).foregroundStyle(StayPalette.inkSecondary).multilineTextAlignment(.center)
            if case .failed(let message) = state {
                Text(message).font(StayFont.callout).foregroundStyle(StayPalette.alert).multilineTextAlignment(.center)
            }
            Spacer()
            Button(state == .joining ? String(localized: "Pairing…") : String(localized: "Pair this device")) {
                state = .joining
                Task {
                    do {
                        model.setRole(.camera)
                        try await model.joinPairing(payload)
                        if !model.preferences.hasCompletedOnboarding { model.completeOnboarding() }
                        dismiss()
                    } catch {
                        state = .failed(error.localizedDescription)
                    }
                }
            }
            .buttonStyle(.stayPrimary)
            .disabled(state == .joining)
            Button("Cancel") { dismiss() }.font(StayFont.headline)
        }
        .padding(24)
        .stayBackground()
    }
}

// MARK: - QR scanner

struct QRScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ controller: QRScannerController, context: Context) {
        controller.onCode = onCode
    }
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private let queue = DispatchQueue(label: "stay.qr")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        self.preview = preview
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let session = session
        queue.async { if !session.isRunning { session.startRunning() } }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue
        MainActor.assumeIsolated {
            if let value { onCode?(value) }
        }
    }
}

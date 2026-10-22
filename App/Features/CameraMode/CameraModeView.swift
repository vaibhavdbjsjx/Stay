@preconcurrency import AVFoundation
import SwiftUI

/// The spare device's home: setup checklist, then a dimmed monitoring screen.
struct CameraModeView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false
    @State private var showPairing = false

    private var camera: CameraController { model.camera }

    var body: some View {
        Group {
            if camera.state == .idle || camera.state == .starting {
                setup
            } else {
                MonitoringScreen()
            }
        }
        .animation(.easeInOut(duration: 0.4), value: camera.state)
        .sheet(isPresented: $showSettings) { CameraSettingsSheet() }
        .sheet(isPresented: $showPairing) {
            NavigationStack {
                ScanPairingView(onPaired: { showPairing = false })
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showPairing = false } } }
            }
        }
    }

    private var setup: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dog camera").eyebrowStyle(StayPalette.apricot)
                        Text("Set up the camera spot").font(StayFont.hero)
                        Text("Place this device where it can see your dog's usual resting area, ideally on a shelf at chest height.")
                            .font(StayFont.callout).foregroundStyle(StayPalette.inkSecondary)
                    }
                    CameraPreviewCard()
                    VStack(alignment: .leading, spacing: 14) {
                        SetupLine(symbol: "powerplug.fill", title: String(localized: "Keep it plugged in"), detail: String(localized: "Monitoring uses the camera and microphone continuously."), done: camera.isCharging)
                        SetupLine(symbol: "thermometer.medium", title: String(localized: "Out of direct sun"), detail: String(localized: "Heat can make iOS stop the camera. Remove thick cases."), done: !camera.hasThermalWarning)
                        SetupLine(symbol: "lock.rectangle.on.rectangle", title: String(localized: "Turn on Guided Access"), detail: String(localized: "Settings → Accessibility → Guided Access, then triple-click the side button. It keeps Stay on screen so the camera can't stop."), done: UIAccessibility.isGuidedAccessEnabled)
                        SetupLine(symbol: "speaker.slash.fill", title: String(localized: "Silence notifications"), detail: String(localized: "Use a Focus so sounds from this device don't disturb your dog."), done: nil)
                    }
                    .stayCard()
                    pairingCard
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sensitivity").font(StayFont.headline)
                        Picker("Sensitivity", selection: Binding(get: { camera.sensitivity }, set: { camera.updateSensitivity($0) })) {
                            ForEach(DetectionSensitivity.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Text(camera.sensitivity.detail).font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
                        Text("Your phone's setting for each dog is used during missions.").font(StayFont.caption).foregroundStyle(StayPalette.inkTertiary)
                    }
                    .stayCard()
                    Text("Stay must stay open on screen to use the camera — iOS doesn't allow the camera in the background. Analysis happens on this device; nothing is recorded continuously.")
                        .font(StayFont.caption)
                        .foregroundStyle(StayPalette.inkSecondary)
                }
                .padding(20)
            }
            .stayBackground()
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await camera.arm() }
                } label: {
                    if camera.state == .starting {
                        ProgressView().tint(.white)
                    } else {
                        Label("Arm camera", systemImage: "video.fill")
                    }
                }
                .buttonStyle(.stayPrimary(StayPalette.apricot))
                .disabled(camera.state == .starting)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel(Text("Settings"))
                }
            }
            .onAppear {
                UIDevice.current.isBatteryMonitoringEnabled = true
            }
        }
    }

    private var pairingCard: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: model.isPaired ? "link" : "qrcode.viewfinder", tint: model.isPaired ? StayPalette.calm : StayPalette.apricot, fill: (model.isPaired ? StayPalette.calm : StayPalette.apricot).opacity(0.14))
            VStack(alignment: .leading, spacing: 2) {
                Text(model.isPaired ? String(localized: "Paired with \(model.preferences.link?.partnerName ?? String(localized: "your phone"))") : String(localized: "Not paired yet"))
                    .font(StayFont.bodyEmphasis)
                Text(pairingDetail).font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
            }
            Spacer()
            Button(model.isPaired ? String(localized: "Re-pair") : String(localized: "Pair")) { showPairing = true }
                .buttonStyle(.bordered)
        }
        .stayCard()
    }

    private var pairingDetail: String {
        switch model.preferences.link?.database {
        case .privateDB, .sharedDB: String(localized: "Alerts over iCloud and Wi-Fi")
        case .nearbyOnly: String(localized: "Wi-Fi only — sign in to iCloud for remote alerts")
        case nil: String(localized: "Scan the code from your phone to get alerts")
        }
    }
}

private struct SetupLine: View {
    var symbol: String
    var title: String
    var detail: String
    var done: Bool?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(symbol: symbol, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(StayFont.bodyEmphasis)
                Text(detail).font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
            }
            Spacer()
            if let done {
                Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(done ? StayPalette.calm : StayPalette.inkTertiary)
                    .accessibilityLabel(done ? Text("Done") : Text("Not yet"))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Camera preview during setup, using a separate lightweight capture session.
private struct CameraPreviewCard: View {
    @State private var authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black)
            if authorized, AVCaptureDevice.default(for: .video) != nil {
                PreviewSessionView()
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "video.slash.fill").font(.largeTitle)
                    Text(AVCaptureDevice.default(for: .video) == nil
                         ? String(localized: "No camera on this device. Sound detection still works.")
                         : String(localized: "Allow camera access in Settings to see the preview."))
                        .font(StayFont.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    if AVCaptureDevice.default(for: .video) != nil {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                }
                .foregroundStyle(.white.opacity(0.8))
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityLabel(Text("Camera preview"))
    }
}

private struct PreviewSessionView: UIViewRepresentable {
    func makeUIView(context: Context) -> PreviewUIView { PreviewUIView() }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewUIView, coordinator: ()) {
        uiView.stop()
    }
}

final class PreviewUIView: UIView {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "stay.preview")
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    init() {
        super.init(frame: .zero)
        let layer = layer as! AVCaptureVideoPreviewLayer
        layer.videoGravity = .resizeAspectFill
        layer.session = session
        let session = session
        queue.async {
            session.sessionPreset = .medium
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
               let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
            }
            session.startRunning()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func stop() {
        let session = session
        queue.async { session.stopRunning() }
    }
}

// MARK: - Monitoring

private struct MonitoringScreen: View {
    @Environment(AppModel.self) private var model
    @State private var dimmed = false
    @State private var lastTouch = Date.now
    @State private var confirmStop = false

    private var camera: CameraController { model.camera }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 28) {
                HStack {
                    statusPill
                    Spacer()
                    batteryLabel
                }
                Spacer()
                breathingMark
                VStack(spacing: 8) {
                    Text(title).font(StayFont.display).foregroundStyle(.white)
                    Text(subtitle).font(StayFont.callout).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                }
                if camera.isRunning, let start = camera.currentStart {
                    TimelineView(.periodic(from: start.startedAt, by: 1)) { context in
                        Text(DurationText.clock(context.date.timeIntervalSince(start.startedAt)))
                            .font(StayFont.timer)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                LevelSparkline(levels: camera.levelHistory, tint: StayPalette.sage, highlight: StayPalette.apricot)
                    .frame(height: 44)
                    .padding(.horizontal, 30)
                if camera.hasThermalWarning {
                    Label("This device is getting warm. Move it out of the sun or remove its case.", systemImage: "thermometer.high")
                        .font(StayFont.caption).foregroundStyle(StayPalette.apricot)
                }
                if !camera.isCharging, camera.batteryLevel >= 0, camera.batteryLevel < 0.3 {
                    Label("Battery low — plug in to keep monitoring.", systemImage: "battery.25")
                        .font(StayFont.caption).foregroundStyle(StayPalette.apricot)
                }
                ForEach(issueTexts, id: \.self) { text in
                    Label(text, systemImage: "exclamationmark.triangle")
                        .font(StayFont.caption).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                HStack(spacing: 12) {
                    if camera.isRunning {
                        Button("End session") { confirmStop = true }
                            .buttonStyle(.stayPrimary(StayPalette.alert))
                    }
                    Button("Disarm") { camera.disarm() }
                        .buttonStyle(.stayPrimary(.white.opacity(0.15)))
                }
                Text("Tap anywhere to wake the screen").font(StayFont.caption).foregroundStyle(.white.opacity(0.4))
            }
            .padding(24)
            .opacity(dimmed ? 0.12 : 1)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(dimmed)
        .persistentSystemOverlays(.hidden)
        .contentShape(Rectangle())
        .onTapGesture {
            lastTouch = .now
            withAnimation(.easeInOut(duration: 0.4)) { dimmed = false }
        }
        .task {
            // Dim after 15 s without a touch to save power and avoid lighting the room.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Date.now.timeIntervalSince(lastTouch) > 15, !dimmed {
                    withAnimation(.easeInOut(duration: 1.2)) { dimmed = true }
                }
            }
        }
        .confirmationDialog("End this session?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("End session", role: .destructive) { camera.stopFromCamera() }
        } message: {
            Text("Your phone will be told the camera stopped.")
        }
    }

    private var title: String {
        if let start = camera.currentStart {
            return start.dogName.isEmpty ? String(localized: "Watching") : String(localized: "Watching \(start.dogName)")
        }
        return String(localized: "Armed and waiting")
    }

    private var subtitle: String {
        if camera.isRunning {
            let count = camera.sessionEvents.count
            return count == 0 ? String(localized: "All calm. Alerts go straight to your phone.") : String(localized: "\(count) moments sent to your phone")
        }
        if let summary = camera.lastSessionSummary {
            return String(localized: "Last session: \(DurationText.short(summary.duration)), \(summary.events) alerts. Start the next mission from your phone.")
        }
        return model.isPaired
            ? String(localized: "Start a mission from your phone and this camera begins automatically.")
            : String(localized: "Pair with your phone first so missions can start here.")
    }

    private var statusPill: some View {
        let connected = model.nearby.isConnected
        return HStack(spacing: 6) {
            Circle().fill(camera.isRunning ? StayPalette.apricot : StayPalette.calm).frame(width: 8, height: 8)
            Text(camera.isRunning ? String(localized: "Monitoring") : String(localized: "Armed"))
            if connected { Image(systemName: "wifi") }
            if model.preferences.link?.database == .privateDB || model.preferences.link?.database == .sharedDB { Image(systemName: "icloud") }
        }
        .font(StayFont.captionEmphasis)
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.white.opacity(0.1), in: Capsule())
    }

    private var batteryLabel: some View {
        Label(camera.batteryLevel >= 0 ? "\(Int(camera.batteryLevel * 100))%" : "—", systemImage: camera.isCharging ? "battery.100.bolt" : "battery.50")
            .font(StayFont.captionEmphasis)
            .foregroundStyle(.white.opacity(0.7))
    }

    private var breathingMark: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { context in
            let phase = (sin(context.date.timeIntervalSinceReferenceDate * 0.9) + 1) / 2
            StayMark(houseColor: .white.opacity(0.5 + phase * 0.3), dogColor: camera.isRunning ? StayPalette.apricot : StayPalette.sage, faceColor: .black)
                .frame(width: 120, height: 120)
                .scaleEffect(0.96 + phase * 0.06)
        }
        .accessibilityHidden(true)
    }

    private var issueTexts: [String] {
        camera.issues.map { issue in
            switch issue {
            case .noCamera: String(localized: "No camera — pacing detection and live view are off.")
            case .noMicrophone: String(localized: "Microphone unavailable — check permission in Settings.")
            case .soundAnalysisUnavailable: String(localized: "Sound detection isn't available on this device.")
            }
        }
    }
}

private struct CameraSettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSwitch = false

    var body: some View {
        NavigationStack {
            Form {
                Section("This device") {
                    LabeledContent("Role", value: DeviceRole.camera.title)
                    Button("Use as my phone instead") { confirmSwitch = true }
                }
                if model.isPaired {
                    Section {
                        Button("Unpair", role: .destructive) { model.unpair() }
                    }
                }
                LegalLinksSection()
            }
            .navigationTitle("Camera settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Switch this device to “my phone”?", isPresented: $confirmSwitch, titleVisibility: .visible) {
                Button("Switch") {
                    dismiss()
                    model.setRole(.owner)
                    if model.dogs.isEmpty { model.updatePreferences { $0.hasCompletedOnboarding = false } }
                }
            }
        }
    }
}

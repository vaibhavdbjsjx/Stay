import AVFoundation
import PhotosUI
import SwiftUI

struct OnboardingFlow: View {
    @Environment(AppModel.self) private var model

    enum Step: Hashable {
        case welcome
        case role
        case profile
        case questionnaire
        case result
        case ownerPermissions
        case cameraPermissions
        case cameraPairing
    }

    @State private var path: [Step] = []
    @State private var draft = DogDraft()
    @State private var createdDog: Dog?

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeStep { path.append(.role) }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .welcome:
                        WelcomeStep { path.append(.role) }
                    case .role:
                        RoleStep { role in
                            model.setRole(role)
                            path.append(role == .owner ? .profile : .cameraPermissions)
                        }
                    case .profile:
                        DogProfileStep(draft: $draft) { path.append(.questionnaire) }
                    case .questionnaire:
                        QuestionnaireView(dogName: draft.name, answers: $draft.answers) { path.append(.result) }
                    case .result:
                        AssessmentResultStep(draft: draft) {
                            if createdDog == nil {
                                createdDog = model.addDog(name: draft.name, breed: draft.breed, years: draft.years, months: draft.months, photo: draft.photo, answers: draft.answers)
                            }
                            path.append(.ownerPermissions)
                        }
                    case .ownerPermissions:
                        OwnerPermissionsStep { model.completeOnboarding() }
                    case .cameraPermissions:
                        CameraPermissionsStep { path.append(.cameraPairing) }
                    case .cameraPairing:
                        CameraPairingStep { model.completeOnboarding() }
                    }
                }
        }
    }
}

/// Fields collected while creating a dog profile.
struct DogDraft {
    var name = ""
    var breed = ""
    var years = 2
    var months = 0
    var photo: UIImage?
    var answers: [String: Int] = [:]
}

// MARK: - Welcome

private struct WelcomeStep: View {
    var next: () -> Void
    @State private var appeared = false

    var body: some View {
        ZStack {
            StayPalette.heroGradient.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                StayMark(faceColor: Color(hex: 0x24443B))
                    .frame(width: 180, height: 180)
                    .scaleEffect(appeared ? 1 : 0.85)
                    .opacity(appeared ? 1 : 0)
                VStack(spacing: 14) {
                    Text("Stay")
                        .font(.system(size: 52, weight: .semibold, design: .serif))
                        .foregroundStyle(StayPalette.cream)
                    Text("A calm, step-by-step coach for dogs who find it hard to be home alone.")
                        .font(StayFont.body)
                        .foregroundStyle(StayPalette.cream.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                Spacer()
                VStack(alignment: .leading, spacing: 14) {
                    FeatureLine(symbol: "figure.walk.departure", text: String(localized: "Daily missions that grow at your dog's pace"))
                    FeatureLine(symbol: "waveform", text: String(localized: "A spare phone listens and watches for stress"))
                    FeatureLine(symbol: "bell.badge", text: String(localized: "Gentle alerts and a live view while you're out"))
                }
                .padding(.horizontal, 32)
                .opacity(appeared ? 1 : 0)
                Button("Get started", action: next)
                    .buttonStyle(.stayPrimary(StayPalette.apricot))
                    .padding(.horizontal, 24)
                Text("Training support, not a medical treatment. Talk to your vet about severe anxiety.")
                    .font(StayFont.caption)
                    .foregroundStyle(StayPalette.cream.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 8)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.1)) { appeared = true }
        }
    }
}

private struct FeatureLine: View {
    var symbol: String
    var text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(StayPalette.apricot)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(StayFont.callout)
                .foregroundStyle(StayPalette.cream)
        }
    }
}

// MARK: - Role

private struct RoleStep: View {
    var choose: (DeviceRole) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                OnboardingHeader(
                    eyebrow: String(localized: "Step 1"),
                    title: String(localized: "How will you use this device?"),
                    message: String(localized: "Stay works best with two devices: your phone, and a spare iPhone or iPad that stays home as the dog camera. You can change this later.")
                )
                RoleCard(
                    symbol: "iphone",
                    title: String(localized: "This is my phone"),
                    detail: String(localized: "Plan missions, get alerts and see a live view while you're out."),
                    action: { choose(.owner) }
                )
                RoleCard(
                    symbol: "video.fill",
                    title: String(localized: "This is the dog camera"),
                    detail: String(localized: "A spare iPhone or iPad that stays home, plugged in, watching and listening for stress."),
                    action: { choose(.camera) }
                )
                Label("Only have one device? Choose “my phone” and you can still run missions and note what you see.", systemImage: "info.circle")
                    .font(StayFont.caption)
                    .foregroundStyle(StayPalette.inkSecondary)
            }
            .padding(24)
        }
        .stayBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RoleCard: View {
    var symbol: String
    var title: String
    var detail: String
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            HStack(alignment: .top, spacing: 16) {
                IconBadge(symbol: symbol, size: 52)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(StayFont.headline).foregroundStyle(StayPalette.ink)
                    Text(detail).font(StayFont.callout).foregroundStyle(StayPalette.inkSecondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(StayPalette.inkTertiary).padding(.top, 4)
            }
            .stayCard()
        }
        .buttonStyle(.plain)
    }
}

struct OnboardingHeader: View {
    var eyebrow: String
    var title: String
    var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow).eyebrowStyle(StayPalette.apricot)
            Text(title).font(StayFont.display).foregroundStyle(StayPalette.ink)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message).font(StayFont.body).foregroundStyle(StayPalette.inkSecondary)
            }
        }
    }
}

// MARK: - Dog profile

private struct DogProfileStep: View {
    @Binding var draft: DogDraft
    var next: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                OnboardingHeader(
                    eyebrow: String(localized: "Step 2"),
                    title: String(localized: "Tell us about your dog"),
                    message: String(localized: "This personalises the plan, your reminders and the progress cards you can share.")
                )
                DogProfileForm(draft: $draft)
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Continue", action: next)
                .buttonStyle(.stayPrimary)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .background(StayPalette.canvas.opacity(0.95))
        }
        .stayBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Name, photo, age and breed. Shared by onboarding and "Add a dog".
struct DogProfileForm: View {
    @Binding var draft: DogDraft
    @State private var pickerItem: PhotosPickerItem?
    @FocusState private var focused: Field?

    enum Field { case name, breed }

    var body: some View {
        let currentPhoto = draft.photo
        VStack(spacing: 20) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let photo = currentPhoto {
                            Image(uiImage: photo).resizable().scaledToFill()
                        } else {
                            ZStack {
                                StayPalette.apricotSoft
                                Image(systemName: "pawprint.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(StayPalette.apricot)
                            }
                        }
                    }
                    .frame(width: 128, height: 128)
                    .clipShape(Circle())
                    Image(systemName: currentPhoto == nil ? "plus.circle.fill" : "pencil.circle.fill")
                        .font(.system(size: 34))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, StayPalette.sage)
                }
            }
            .accessibilityLabel(draft.photo == nil ? Text("Add a photo") : Text("Change photo"))
            .frame(maxWidth: .infinity)
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        draft.photo = image
                    }
                }
            }

            VStack(spacing: 0) {
                FormRow(title: String(localized: "Name")) {
                    TextField("e.g. Biscuit", text: $draft.name)
                        .textContentType(.name)
                        .submitLabel(.next)
                        .focused($focused, equals: .name)
                        .onSubmit { focused = .breed }
                }
                Divider().padding(.leading, 16)
                FormRow(title: String(localized: "Breed")) {
                    TextField("e.g. Cocker Spaniel", text: $draft.breed)
                        .submitLabel(.done)
                        .focused($focused, equals: .breed)
                }
                Divider().padding(.leading, 16)
                FormRow(title: String(localized: "Age")) {
                    HStack {
                        Picker("Years", selection: $draft.years) {
                            ForEach(0..<21) { Text("\($0) y").tag($0) }
                        }
                        Picker("Months", selection: $draft.months) {
                            ForEach(0..<12) { Text("\($0) m").tag($0) }
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .background(StayPalette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(StayPalette.hairline))
        }
    }
}

struct FormRow<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(StayFont.bodyEmphasis).foregroundStyle(StayPalette.ink).frame(width: 70, alignment: .leading)
            content.font(StayFont.body).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
    }
}

// MARK: - Questionnaire

struct QuestionnaireView: View {
    var dogName: String
    @Binding var answers: [String: Int]
    var finish: () -> Void
    @State private var index = 0

    private var questions: [SeverityQuestion] { SeverityQuestionnaire.questions(dogName: dogName.isEmpty ? String(localized: "your dog") : dogName) }

    var body: some View {
        let question = questions[index]
        VStack(alignment: .leading, spacing: 24) {
            ProgressView(value: Double(index + 1), total: Double(questions.count))
                .tint(StayPalette.apricot)
                .accessibilityLabel(Text("Question \(index + 1) of \(questions.count)"))
            OnboardingHeader(eyebrow: String(localized: "Question \(index + 1) of \(questions.count)"), title: question.prompt)
                .id(question.id)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            VStack(spacing: 12) {
                ForEach(question.options.indices, id: \.self) { option in
                    let selected = answers[question.id] == option
                    Button {
                        Haptics.select()
                        answers[question.id] = option
                        advance()
                    } label: {
                        HStack {
                            Text(question.options[option].title)
                                .font(StayFont.bodyEmphasis)
                                .foregroundStyle(StayPalette.ink)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected ? StayPalette.sage : StayPalette.inkTertiary)
                        }
                        .padding(18)
                        .background(selected ? StayPalette.sageSoft : StayPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? StayPalette.sage : StayPalette.hairline))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .id(question.id + "-options")
            Spacer()
            if index > 0 {
                Button("Previous question") {
                    withAnimation { index -= 1 }
                }
                .font(StayFont.callout)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .stayBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func advance() {
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            if index < questions.count - 1 {
                withAnimation(.easeInOut(duration: 0.3)) { index += 1 }
            } else {
                finish()
            }
        }
    }
}

// MARK: - Result

private struct AssessmentResultStep: View {
    var draft: DogDraft
    var next: () -> Void

    var body: some View {
        let assessment = SeverityQuestionnaire.assess(answers: draft.answers, dogName: draft.name)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                OnboardingHeader(eyebrow: String(localized: "Your starting point"), title: String(localized: "\(draft.name)'s plan is ready"))
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Starting level").font(StayFont.callout).foregroundStyle(StayPalette.inkSecondary)
                        Spacer()
                        Pill(text: assessment.level.title, tint: tint(assessment.level), fill: tint(assessment.level).opacity(0.14))
                    }
                    Text(assessment.level.summary).font(StayFont.body).foregroundStyle(StayPalette.ink)
                }
                .stayCard()
                if assessment.recommendsVet {
                    HStack(alignment: .top, spacing: 14) {
                        IconBadge(symbol: "cross.case.fill", tint: StayPalette.alert, fill: StayPalette.alert.opacity(0.12))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Please also talk to your vet").font(StayFont.headline)
                            Text("Some answers suggest \(draft.name) gets very distressed or has been hurt. A vet can check for pain and talk about support that works alongside training. Stay is training support, not a medical treatment.")
                                .font(StayFont.callout).foregroundStyle(StayPalette.inkSecondary)
                        }
                    }
                    .stayCard(fill: StayPalette.alert.opacity(0.06))
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("How it works").font(StayFont.title)
                    StepLine(number: 1, title: String(localized: "Baseline"), detail: String(localized: "One short session shows how long \(draft.name) can be alone right now."))
                    StepLine(number: 2, title: String(localized: "Daily missions"), detail: String(localized: "Each calm session grows the next one by 10–20%. Stress means a small step back."))
                    StepLine(number: 3, title: String(localized: "Departure cues"), detail: String(localized: "Keys, shoes and the door become boring through quick practice."))
                    StepLine(number: 4, title: String(localized: "Rest days"), detail: String(localized: "Built in, so progress sticks."))
                }
                .stayCard()
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Continue", action: next)
                .buttonStyle(.stayPrimary)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        }
        .stayBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tint(_ level: SeverityLevel) -> Color {
        switch level {
        case .mild: StayPalette.calm
        case .moderate: StayPalette.amber
        case .severe: StayPalette.alert
        }
    }
}

private struct StepLine: View {
    var number: Int
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(StayFont.captionEmphasis)
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(StayPalette.sage, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(StayFont.bodyEmphasis).foregroundStyle(StayPalette.ink)
                Text(detail).font(StayFont.callout).foregroundStyle(StayPalette.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Permissions

private struct OwnerPermissionsStep: View {
    var finish: () -> Void
    @State private var asked = false

    var body: some View {
        PermissionExplainer(
            symbol: "bell.badge.fill",
            title: String(localized: "Stay in the loop"),
            message: String(localized: "Notifications let Stay remind you about today's mission, tell you when it's time to head back, and alert you if your dog seems stressed while you're out."),
            bullets: [
                String(localized: "One gentle reminder a day, at a time you choose"),
                String(localized: "A nudge when the mission time is up"),
                String(localized: "Alerts from your dog camera"),
            ],
            primaryTitle: String(localized: "Allow notifications"),
            secondaryTitle: String(localized: "Not now"),
            primary: {
                Task {
                    await NotificationScheduler.requestAuthorization()
                    finish()
                }
            },
            secondary: finish
        )
    }
}

private struct CameraPermissionsStep: View {
    var next: () -> Void

    var body: some View {
        PermissionExplainer(
            symbol: "video.badge.waveform.fill",
            title: String(localized: "Turn this device into a dog camera"),
            message: String(localized: "Next, iOS will ask for the camera, microphone and local network. Everything is analysed on this device. Stay never records continuously and never uploads audio."),
            bullets: [
                String(localized: "Camera: watches for pacing and shows a live view"),
                String(localized: "Microphone: listens for barking, howling and whining"),
                String(localized: "Local network: streams to your phone on the same Wi-Fi"),
            ],
            primaryTitle: String(localized: "Continue"),
            secondaryTitle: nil,
            primary: {
                Task {
                    _ = await AVCaptureDevice.requestAccess(for: .video)
                    _ = await AVCaptureDevice.requestAccess(for: .audio)
                    await NotificationScheduler.requestAuthorization()
                    next()
                }
            },
            secondary: {}
        )
    }
}

struct PermissionExplainer: View {
    var symbol: String
    var title: String
    var message: String
    var bullets: [String]
    var primaryTitle: String
    var secondaryTitle: String?
    var primary: () -> Void
    var secondary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            ZStack {
                Circle().fill(StayPalette.sageSoft).frame(width: 110, height: 110)
                Image(systemName: symbol)
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(StayPalette.sage)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
            Text(title).font(StayFont.display).foregroundStyle(StayPalette.ink).accessibilityAddTraits(.isHeader)
            Text(message).font(StayFont.body).foregroundStyle(StayPalette.inkSecondary)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(bullets, id: \.self) { bullet in
                    Label(bullet, systemImage: "checkmark.circle.fill")
                        .font(StayFont.callout)
                        .foregroundStyle(StayPalette.ink)
                        .symbolRenderingMode(.multicolor)
                }
            }
            Spacer()
            Button(primaryTitle, action: primary).buttonStyle(.stayPrimary)
            if let secondaryTitle {
                Button(secondaryTitle, action: secondary)
                    .font(StayFont.headline)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .stayBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Camera pairing (onboarding)

private struct CameraPairingStep: View {
    var finish: () -> Void

    var body: some View {
        ScanPairingView(onPaired: finish, onSkip: finish)
            .navigationBarTitleDisplayMode(.inline)
    }
}

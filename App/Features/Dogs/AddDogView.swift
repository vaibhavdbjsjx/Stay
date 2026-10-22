import SwiftUI

/// Add another dog: profile, then the same intake questionnaire.
struct AddDogView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = DogDraft()
    @State private var step = 0

    var body: some View {
        NavigationStack {
            Group {
                if step == 0 {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            OnboardingHeader(eyebrow: String(localized: "New dog"), title: String(localized: "Who's joining?"))
                            DogProfileForm(draft: $draft)
                        }
                        .padding(24)
                    }
                    .safeAreaInset(edge: .bottom) {
                        Button("Continue") { withAnimation { step = 1 } }
                            .buttonStyle(.stayPrimary)
                            .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 8)
                    }
                } else {
                    QuestionnaireView(dogName: draft.name, answers: $draft.answers) {
                        model.addDog(name: draft.name, breed: draft.breed, years: draft.years, months: draft.months, photo: draft.photo, answers: draft.answers)
                        Haptics.success()
                        dismiss()
                    }
                }
            }
            .stayBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

/// Edit a dog's profile, plan settings and detection sensitivity.
struct DogSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var dog: Dog
    @State private var confirmDelete = false
    @State private var retakeQuestionnaire = false
    @State private var photoDraft = DogDraft()

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    DogProfileForm(draft: $photoDraft)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            Section("Plan") {
                LabeledContent("Starting level", value: dog.severity.title)
                LabeledContent("Current mission", value: dog.plan.phase == .needsBaseline ? String(localized: "Baseline") : DurationText.short(dog.plan.targetSeconds))
                Button("Retake the questionnaire") { retakeQuestionnaire = true }
            }
            Section {
                ForEach(1...7, id: \.self) { weekday in
                    Toggle(Calendar.current.weekdaySymbols[weekday - 1], isOn: Binding(
                        get: { dog.restWeekdays.contains(weekday) },
                        set: { isOn in
                            if isOn { dog.restWeekdays.insert(weekday) } else { dog.restWeekdays.remove(weekday) }
                        }
                    ))
                }
            } header: {
                Text("Rest days")
            } footer: {
                Text("Stay also adds a rest day after five training days in a row, and after two tough sessions.")
            }
            Section {
                Picker("Detection sensitivity", selection: $dog.sensitivity) {
                    ForEach(DetectionSensitivity.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Detection sensitivity")
            } footer: {
                Text(dog.sensitivity.detail)
            }
            Section {
                Button("Delete \(dog.name)", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Deletes this dog's profile, sessions, journal and photos from this device.")
            }
        }
        .scrollContentBackground(.hidden)
        .stayBackground()
        .navigationTitle(dog.name)
        .onAppear {
            photoDraft = DogDraft(name: dog.name, breed: dog.breed, years: dog.ageYears, months: dog.ageMonths, photo: model.photo(for: dog))
        }
        .onDisappear(perform: save)
        .sheet(isPresented: $retakeQuestionnaire) {
            NavigationStack {
                QuestionnaireView(dogName: dog.name, answers: $dog.assessment.answers) {
                    dog.assessment = SeverityQuestionnaire.assess(answers: dog.assessment.answers, dogName: dog.name)
                    retakeQuestionnaire = false
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { retakeQuestionnaire = false } } }
            }
        }
        .confirmationDialog("Delete \(dog.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.deleteDog(dog.id)
                dismiss()
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    private func save() {
        guard model.dogs.contains(where: { $0.id == dog.id }) else { return }
        var updated = dog
        let name = photoDraft.name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { updated.name = name }
        updated.breed = photoDraft.breed
        updated.ageYears = photoDraft.years
        updated.ageMonths = photoDraft.months
        model.updateDog(updated)
        if let photo = photoDraft.photo, photo !== model.photo(for: dog) {
            model.setPhoto(photo, for: dog.id)
        }
    }
}

import SwiftUI

struct SunoGeneratorView: View {
    let lyrics: String
    let detectedBPM: Double?
    let detectedKey: String?
    var onPromptGenerated: ((String, String, Bool) -> Void)?
    @StateObject private var model: SunoViewModel
    @State private var bpmText: String
    @State private var musicalKey: String

    init(
        lyrics: String,
        detectedBPM: Double?,
        detectedKey: String?,
        initialPrompt: String = "",
        initialReferenceArtist: String = "",
        initialAllowsFemaleBackingVocals: Bool = false,
        onPromptGenerated: ((String, String, Bool) -> Void)? = nil
    ) {
        self.lyrics = lyrics
        self.detectedBPM = detectedBPM
        self.detectedKey = detectedKey
        self.onPromptGenerated = onPromptGenerated
        _model = StateObject(wrappedValue: SunoViewModel(
            referenceArtist: initialReferenceArtist,
            allowsFemaleBackingVocals: initialAllowsFemaleBackingVocals,
            generatedPrompt: initialPrompt
        ))
        _bpmText = State(initialValue: detectedBPM.map(Self.formatBPM) ?? "")
        _musicalKey = State(initialValue: detectedKey ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                intro
                settingsCard
                vocalLockCard
                actionBar
                if model.hasPrompt { promptResult }
            }
            .frame(maxWidth: 900)
            .padding(30)
            .frame(maxWidth: .infinity)
        }
        .alert("Logic Lyrics", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .onChange(of: detectedBPM) { _, value in
            bpmText = value.map(Self.formatBPM) ?? ""
        }
        .onChange(of: detectedKey) { _, value in
            musicalKey = value ?? ""
        }
        .onChange(of: model.generatedPrompt) { _, prompt in
            guard !prompt.isEmpty else { return }
            onPromptGenerated?(prompt, model.referenceArtist, model.allowsFemaleBackingVocals)
        }
    }

    private var intro: some View {
        HStack(alignment: .top, spacing: 16) {
            AccentIcon(systemName: "sparkles", color: AppTheme.accent, size: 48)
            VStack(alignment: .leading, spacing: 5) {
                Text("Prepare for Suno AI")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("A complete prompt for ChatGPT or Gemini, with no API key required.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 7) {
                CapsuleStatus(text: "Voice protected", systemName: "lock.fill", color: AppTheme.green)
                CapsuleStatus(
                    text: L10n.format("%d characters imported", lyrics.count),
                    systemName: lyrics.isEmpty ? "exclamationmark.triangle.fill" : "text.badge.checkmark",
                    color: lyrics.isEmpty ? AppTheme.coral : AppTheme.cyan
                )
            }
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            cardTitle(L10n.text("Art Direction"), subtitle: L10n.text("The reference is translated into broad musical characteristics."), icon: "slider.horizontal.3")

            VStack(alignment: .leading, spacing: 7) {
                Text("REFERENCE BAND OR ARTIST")
                    .font(.caption2.weight(.bold)).tracking(0.7).foregroundStyle(.secondary)
                TextField("e.g. Phoenix, Tame Impala…", text: $model.referenceArtist)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium))
                    .padding(13)
                    .background(Color.primary.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 11).stroke(Color.primary.opacity(0.09)) }
            }

            HStack(spacing: 12) {
                metadataField("BPM", placeholder: "e.g. 140", text: $bpmText, width: 150)
                metadataField("KEY", placeholder: "e.g. C major", text: $musicalKey)
            }
            Text("Both values are required and will be placed at the beginning of Styles.")
                .font(.caption).foregroundStyle(.secondary)

            Toggle(isOn: $model.allowsFemaleBackingVocals) {
                HStack(spacing: 11) {
                    AccentIcon(systemName: "person.2.wave.2", color: AppTheme.coral, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow female backing vocals").font(.subheadline.weight(.semibold))
                        Text(model.allowsFemaleBackingVocals
                             ? L10n.text("Harmonies and responses are allowed, never as lead.")
                             : L10n.text("Male backing vocals only."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.switch)
        }
        .appPanel(radius: 20, padding: 20)
    }

    private var vocalLockCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardTitle(L10n.text("Vocal Lock"), subtitle: L10n.text("High-priority constraints injected into every generation."), icon: "waveform.badge.checkmark")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                rule(L10n.text("Natural baritone"), "music.mic", AppTheme.accent)
                rule(L10n.text("Chest voice"), "waveform", AppTheme.cyan)
                rule(L10n.text("No falsetto or high notes"), "arrow.down.right", AppTheme.green)
                rule(L10n.text("No screaming"), "speaker.slash", AppTheme.coral)
                rule(L10n.text("No vocal acrobatics"), "figure.stand", AppTheme.accent)
                rule(L10n.text("Same lead throughout"), "person.fill.checkmark", AppTheme.cyan)
            }
            Divider().opacity(0.3)
            HStack(spacing: 18) {
                checklist(L10n.text("Add Voice profile"))
                checklist(L10n.text("Voice model"))
                checklist(L10n.text("High Audio Influence"))
            }
        }
        .appPanel(radius: 20, padding: 20)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button("Generate Prompt", systemImage: "sparkles") {
                _ = model.generatePrompt(from: lyrics, bpmText: bpmText, musicalKey: musicalKey)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(lyrics.isEmpty)
            .keyboardShortcut(.return, modifiers: .command)

            Spacer()
            Text("No API key required")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder private var promptResult: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Prompt Ready").font(.title3.weight(.semibold))
                Text("The prompt is copied before the selected service opens.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(model.copiedField == "prompt" ? "Copied" : "Copy", systemImage: "doc.on.doc") {
                model.copyPrompt()
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 8)

        HStack(spacing: 12) {
            Button("Copy and Open ChatGPT", systemImage: "bubble.left.and.bubble.right.fill") {
                model.copyAndOpenChatGPT()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Copy and Open Gemini", systemImage: "sparkle.magnifyingglass") {
                model.copyAndOpenGemini()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }

        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 11) {
                AccentIcon(systemName: "text.quote", color: AppTheme.cyan, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Complete Prompt").font(.headline)
                    Text("Editable before copying").font(.caption).foregroundStyle(.secondary)
                }
            }
            TextEditor(text: $model.generatedPrompt)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 320)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color.black.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel(L10n.text("Generated Suno prompt editor"))
                .accessibilityHint(L10n.text("Review or edit the complete prompt before copying it."))
        }
        .appPanel(radius: 20, padding: 20)
    }

    private func cardTitle(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 11) {
            AccentIcon(systemName: icon, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func rule(_ title: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 18)
            Text(title).font(.caption.weight(.medium))
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func checklist(_ title: String) -> some View {
        Label(title, systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private func metadataField(_ label: String, placeholder: String, text: Binding<String>, width: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.text(label)).font(.caption2.weight(.bold)).tracking(0.7).foregroundStyle(.secondary)
            TextField(L10n.text(placeholder), text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .padding(12)
                .background(Color.primary.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 11).stroke(Color.primary.opacity(0.09)) }
        }
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil)
    }

    private static func formatBPM(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }

}

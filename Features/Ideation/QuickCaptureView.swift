import SwiftUI
import SwiftData

struct QuickCaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Query private var pillars: [ContentPillar]

    @State private var captureType: InspirationSourceType = .text
    @State private var textContent = ""
    @State private var linkURL = ""
    @State private var selectedPillar: ContentPillar?
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    captureTypePicker
                    captureInput
                    pillarPicker
                    noteField
                }
                .padding(Spacing.md)
            }
            .background(colorScheme == .dark ? Color.bgDark : Color.bgLight)
            .navigationTitle("Capture Idea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.brandBrown)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveInspiration() }
                        .font(.headline)
                        .foregroundStyle(.brandBlack)
                        .disabled(!canSave)
                }
            }
        }
    }

    private var captureTypePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach([InspirationSourceType.text, .link, .image, .voiceMemo], id: \.self) { type in
                    FilterChip(title: type.displayName, isSelected: captureType == type) {
                        captureType = type
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var captureInput: some View {
        switch captureType {
        case .text:
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("What's your idea?")
                    .font(AppFont.headline())
                TextEditor(text: $textContent)
                    .font(AppFont.body())
                    .frame(minHeight: 120)
                    .padding(Spacing.xs)
                    .background(colorScheme == .dark ? Color.cardDark : Color.cardLight)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    .overlay {
                        RoundedRectangle(cornerRadius: CornerRadius.medium)
                            .strokeBorder(colorScheme == .dark ? Color.borderDark : Color.borderLight, lineWidth: 0.5)
                    }
            }

        case .link:
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Paste a link")
                    .font(AppFont.headline())
                TextField("https://...", text: $linkURL)
                    .font(AppFont.body())
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocapitalization(.none)
                    .padding(Spacing.sm)
                    .background(colorScheme == .dark ? Color.cardDark : Color.cardLight)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    .overlay {
                        RoundedRectangle(cornerRadius: CornerRadius.medium)
                            .strokeBorder(colorScheme == .dark ? Color.borderDark : Color.borderLight, lineWidth: 0.5)
                    }
            }

        case .image:
            VStack(spacing: Spacing.sm) {
                Text("Add an image")
                    .font(AppFont.headline())
                Button {
                    // TODO: Open photo picker
                } label: {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 32))
                            .foregroundStyle(.brandBrown)
                        Text("Choose from library")
                            .font(AppFont.subhead())
                            .foregroundStyle(.brandBrown)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .background(Color.brandBeige.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
                    .overlay {
                        RoundedRectangle(cornerRadius: CornerRadius.large)
                            .strokeBorder(Color.brandBeige, style: StrokeStyle(lineWidth: 1, dash: [8]))
                    }
                }
            }

        case .voiceMemo:
            VStack(spacing: Spacing.sm) {
                Text("Record a voice memo")
                    .font(AppFont.headline())
                Button {
                    // TODO: Start recording
                } label: {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.brandPink)
                        Text("Tap to record")
                            .font(AppFont.subhead())
                            .foregroundStyle(.brandBrown)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .background(Color.brandPink.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
                }
            }

        default:
            EmptyView()
        }
    }

    private var pillarPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Pillar (optional)")
                .font(AppFont.headline())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(pillars) { pillar in
                        Button {
                            selectedPillar = selectedPillar == pillar ? nil : pillar
                        } label: {
                            PillarBadge(
                                name: pillar.name,
                                color: selectedPillar == pillar ? pillar.color : .textTertiary
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Note (optional)")
                .font(AppFont.headline())
            TextField("Add a quick note...", text: $note)
                .font(AppFont.body())
                .padding(Spacing.sm)
                .background(colorScheme == .dark ? Color.cardDark : Color.cardLight)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .strokeBorder(colorScheme == .dark ? Color.borderDark : Color.borderLight, lineWidth: 0.5)
                }
        }
    }

    private var canSave: Bool {
        switch captureType {
        case .text: !textContent.isEmpty
        case .link: !linkURL.isEmpty
        default: true
        }
    }

    private func saveInspiration() {
        let inspiration: Inspiration
        switch captureType {
        case .text:
            inspiration = Inspiration(sourceType: .text, title: String(textContent.prefix(50)), notes: textContent)
        case .link:
            inspiration = Inspiration(sourceType: .link, sourceURL: linkURL, title: linkURL)
        default:
            inspiration = Inspiration(sourceType: captureType, notes: note.isEmpty ? nil : note)
        }

        inspiration.pillar = selectedPillar
        if !note.isEmpty { inspiration.notes = note }

        modelContext.insert(inspiration)
        dismiss()
    }
}

#Preview {
    QuickCaptureView()
}

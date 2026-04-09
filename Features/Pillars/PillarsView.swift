import SwiftUI
import SwiftData

struct PillarsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \ContentPillar.sortOrder) private var pillars: [ContentPillar]
    @State private var showAddPillar = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                if pillars.isEmpty {
                    emptyState
                } else {
                    ForEach(pillars) { pillar in
                        pillarCard(pillar)
                    }
                }

                AppButton("Add Pillar", style: .secondary, icon: "plus") {
                    showAddPillar = true
                }
            }
            .padding(Spacing.md)
        }
        .background(colorScheme == .dark ? Color.bgDark : Color.bgLight)
        .navigationTitle("Content Pillars")
        .sheet(isPresented: $showAddPillar) {
            PillarEditorView()
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 48))
                .foregroundStyle(Color.brandBeige)
            Text("No pillars yet")
                .font(AppFont.title3())
            Text("Content pillars are the core themes you create around. They help keep your content balanced and on-brand.")
                .font(AppFont.subhead())
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Spacing.xxxl)
    }

    private func pillarCard(_ pillar: ContentPillar) -> some View {
        ContentCard {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(pillar.color)
                    .frame(width: 4, height: 40)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(pillar.name)
                        .font(AppFont.headline())
                    Text("\(Int(pillar.targetPercentage))% target")
                        .font(AppFont.caption())
                        .foregroundStyle(.textSecondary)
                }

                Spacer()

                Text("\(pillar.contentItems.count) posts")
                    .font(AppFont.caption())
                    .foregroundStyle(.textTertiary)
            }
        }
    }
}

struct PillarEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var name = ""
    @State private var description = ""
    @State private var color = Color.blue
    @State private var targetPercentage: Double = 25

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    HStack(spacing: Spacing.sm) {
                        ColorPicker("Color", selection: $color)
                            .labelsHidden()
                            .frame(width: 36, height: 36)

                        TextField("Pillar name", text: $name)
                            .font(AppFont.title3())
                            .padding(Spacing.sm)
                            .background(colorScheme == .dark ? Color.cardDark : Color.cardLight)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Description")
                            .font(AppFont.headline())
                        TextField("What kind of content fits here?", text: $description, axis: .vertical)
                            .font(AppFont.body())
                            .lineLimit(2...4)
                            .padding(Spacing.sm)
                            .background(colorScheme == .dark ? Color.cardDark : Color.cardLight)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Target: \(Int(targetPercentage))% of content")
                            .font(AppFont.headline())
                        Slider(value: $targetPercentage, in: 5...60, step: 5)
                            .tint(.brandPink)
                    }
                }
                .padding(Spacing.md)
            }
            .background(colorScheme == .dark ? Color.bgDark : Color.bgLight)
            .navigationTitle("New Pillar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.brandBrown)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let pillar = ContentPillar(
                            name: name,
                            description: description,
                            targetPercentage: targetPercentage
                        )
                        modelContext.insert(pillar)
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundStyle(.brandBlack)
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        PillarsView()
    }
}

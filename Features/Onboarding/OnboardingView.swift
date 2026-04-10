import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentStep = 0
    @State private var displayName = ""
    @State private var selectedNiche = ""
    @State private var subNiches: [String] = []
    @State private var pillarInputs: [PillarInput] = [
        PillarInput(name: "", colorHex: "6C8EBF"),
        PillarInput(name: "", colorHex: "E8A87C"),
    ]
    @State private var voiceAdjectives: Set<String> = []
    @State private var voiceSample = ""
    @State private var selectedPlatforms: Set<SocialPlatform> = []
    @State private var selectedGoal: CreatorGoal = .growAudience
    @State private var weeklyPostTarget = 3

    let onComplete: () -> Void

    private let totalSteps = 5

    var body: some View {
        VStack(spacing: 0) {
            progressBar

            TabView(selection: $currentStep) {
                welcomeStep.tag(0)
                nicheStep.tag(1)
                pillarsStep.tag(2)
                voiceStep.tag(3)
                platformsStep.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentStep)

            navigationButtons
        }
        .background(colorScheme == .dark ? Color.bgDark : Color.bgLight)
    }

    // MARK: - Progress

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.brandBeige.opacity(0.3))
                    .frame(height: 3)
                Rectangle()
                    .fill(Color.brandPink)
                    .frame(width: geo.size.width * CGFloat(currentStep + 1) / CGFloat(totalSteps), height: 3)
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
        .frame(height: 3)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            SparkPulse(size: 40)
                .padding(.bottom, Spacing.md)
            Text("Meet your agent")
                .font(AppFont.largeTitle())
            Text("agent.cy learns your style, finds your ideas, and keeps you posting.")
                .font(AppFont.body())
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxl)

            VStack(spacing: Spacing.sm) {
                TextField("Your name", text: $displayName)
                    .font(AppFont.body())
                    .padding(Spacing.sm)
                    .background(colorScheme == .dark ? Color.cardDark : Color.cardLight)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    .overlay {
                        RoundedRectangle(cornerRadius: CornerRadius.medium)
                            .strokeBorder(colorScheme == .dark ? Color.borderDark : Color.borderLight, lineWidth: 0.5)
                    }
            }
            .padding(.horizontal, Spacing.xxl)
            Spacer()
        }
    }

    private var nicheStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Your niche")
                        .font(AppFont.title2())
                    Text("What do you create content about?")
                        .font(AppFont.body())
                        .foregroundStyle(Color.textSecondary)
                }

                let niches = ["Lifestyle", "Beauty", "Fitness", "Tech", "Food", "Travel",
                              "Finance", "Education", "Fashion", "Gaming", "Parenting", "Business"]

                FlowLayout(spacing: Spacing.xs) {
                    ForEach(niches, id: \.self) { niche in
                        FilterChip(title: niche, isSelected: selectedNiche == niche) {
                            selectedNiche = niche
                        }
                    }
                }
            }
            .padding(Spacing.md)
        }
    }

    private var pillarsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Content pillars")
                        .font(AppFont.title2())
                    Text("These are the core themes you create around. Add 2-7 pillars.")
                        .font(AppFont.body())
                        .foregroundStyle(Color.textSecondary)
                }

                ForEach($pillarInputs) { $pillar in
                    HStack(spacing: Spacing.xs) {
                        ColorPicker("", selection: $pillar.color)
                            .labelsHidden()
                            .frame(width: 30, height: 30)
                        TextField("Pillar name", text: $pillar.name)
                            .font(AppFont.body())
                            .padding(Spacing.sm)
                            .background(colorScheme == .dark ? Color.cardDark : Color.cardLight)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    }
                }

                if pillarInputs.count < 7 {
                    Button {
                        pillarInputs.append(PillarInput(name: "", colorHex: randomPillarColor()))
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("Add pillar")
                        }
                        .font(AppFont.subhead(.medium))
                        .foregroundStyle(Color.brandBrown)
                    }
                }
            }
            .padding(Spacing.md)
        }
    }

    private var voiceStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Your voice")
                        .font(AppFont.title2())
                    Text("How does your brand sound? Pick 3-5 words.")
                        .font(AppFont.body())
                        .foregroundStyle(Color.textSecondary)
                }

                let adjectives = ["Warm", "Witty", "Professional", "Casual", "Educational",
                                  "Motivational", "Edgy", "Minimalist", "Playful", "Bold",
                                  "Empathetic", "Authoritative", "Relatable", "Aspirational"]

                FlowLayout(spacing: Spacing.xs) {
                    ForEach(adjectives, id: \.self) { adj in
                        FilterChip(title: adj, isSelected: voiceAdjectives.contains(adj)) {
                            if voiceAdjectives.contains(adj) {
                                voiceAdjectives.remove(adj)
                            } else if voiceAdjectives.count < 5 {
                                voiceAdjectives.insert(adj)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Paste a caption you love")
                        .font(AppFont.headline())
                    TextEditor(text: $voiceSample)
                        .font(AppFont.body())
                        .frame(minHeight: 100)
                        .padding(Spacing.xs)
                        .background(colorScheme == .dark ? Color.cardDark : Color.cardLight)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                        .overlay {
                            RoundedRectangle(cornerRadius: CornerRadius.medium)
                                .strokeBorder(colorScheme == .dark ? Color.borderDark : Color.borderLight, lineWidth: 0.5)
                        }
                }
            }
            .padding(Spacing.md)
        }
    }

    private var platformsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Your platforms")
                        .font(AppFont.title2())
                    Text("Where do you publish content?")
                        .font(AppFont.body())
                        .foregroundStyle(Color.textSecondary)
                }

                ForEach(SocialPlatform.allCases) { platform in
                    Button {
                        if selectedPlatforms.contains(platform) {
                            selectedPlatforms.remove(platform)
                        } else {
                            selectedPlatforms.insert(platform)
                        }
                    } label: {
                        ContentCard {
                            HStack(spacing: Spacing.sm) {
                                PlatformIcon(platform: platform, size: 32)
                                Text(platform.displayName)
                                    .font(AppFont.headline())
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: selectedPlatforms.contains(platform) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedPlatforms.contains(platform) ? Color.brandBlack : Color.brandBeige)
                                    .font(.system(size: 22))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Weekly post goal")
                        .font(AppFont.headline())
                    Stepper("\(weeklyPostTarget) posts/week", value: $weeklyPostTarget, in: 1...14)
                        .font(AppFont.body())
                }
                .padding(.top, Spacing.sm)
            }
            .padding(Spacing.md)
        }
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack(spacing: Spacing.md) {
            if currentStep > 0 {
                AppButton("Back", style: .secondary) {
                    currentStep -= 1
                }
            }

            if currentStep < totalSteps - 1 {
                AppButton("Continue", style: .primary) {
                    currentStep += 1
                }
                .disabled(!canAdvance)
            } else {
                AppButton("Get Started", style: .ai, icon: "sparkles") {
                    saveProfile()
                    onComplete()
                }
                .disabled(!canAdvance)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.lg)
    }

    private var canAdvance: Bool {
        switch currentStep {
        case 0: !displayName.isEmpty
        case 1: !selectedNiche.isEmpty
        case 2: pillarInputs.filter({ !$0.name.isEmpty }).count >= 2
        case 3: voiceAdjectives.count >= 3
        case 4: !selectedPlatforms.isEmpty
        default: true
        }
    }

    // MARK: - Save

    private func saveProfile() {
        let profile = CreatorProfile(
            displayName: displayName,
            niche: selectedNiche,
            subNiches: subNiches,
            voiceAdjectives: Array(voiceAdjectives),
            voiceSamples: voiceSample.isEmpty ? [] : [voiceSample],
            primaryGoal: selectedGoal,
            weeklyPostTarget: weeklyPostTarget
        )
        profile.onboardingCompleted = true

        for input in pillarInputs where !input.name.isEmpty {
            let pillar = ContentPillar(
                name: input.name,
                colorHex: input.colorHex
            )
            profile.pillars.append(pillar)
        }

        for platform in selectedPlatforms {
            let account = PlatformAccount(platform: platform)
            profile.platformAccounts.append(account)
        }

        modelContext.insert(profile)
    }

    private func randomPillarColor() -> String {
        let colors = ["E8A87C", "85CDCA", "D4A5A5", "C9B1FF", "FFD93D", "6C8EBF", "F4978E"]
        return colors.randomElement() ?? "6C8EBF"
    }
}

// MARK: - Helpers

struct PillarInput: Identifiable {
    let id = UUID()
    var name: String
    var colorHex: String
    var color: Color {
        get { Color(hex: colorHex) }
        set { } // Color picker binding requires a setter
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}

#Preview {
    OnboardingView {}
}

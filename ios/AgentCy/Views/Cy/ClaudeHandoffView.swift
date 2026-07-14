import SwiftUI
import UIKit

struct ClaudeImportedMessageView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            HStack {
                MetaLabel("From Claude")
                Spacer()
                MetaLabel("Imported")
            }
            Text(text)
                .font(.agentBody)
                .foregroundStyle(Color.agentText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AgentSpacing.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.agentSurface)
        .clipShape(.rect(cornerRadius: AgentRadius.panel))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.panel)
                .stroke(Color.agentBorder, lineWidth: 1)
        }
    }
}

struct ClaudeHandoffView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let request: ClaudeHandoffRequest
    let onImport: (String) -> Void

    @State private var response = ""
    @State private var copiedPrompt = false
    @FocusState private var responseIsFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                    EditorialHeader(
                        kicker: "Claude subscription",
                        title: "Continue in Claude.",
                        subtitle: "Use the Claude access you already pay for."
                    )

                    VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                        SectionRuleHeader(title: "Send")

                        Text("Choose Claude in the share sheet. Your prepared prompt includes only the context shown below.")
                            .font(.agentBody)
                            .foregroundStyle(Color.agentSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        ShareLink(item: request.prompt) {
                            Label("Send to Claude", systemImage: "arrow.up.forward")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AgentPrimaryButtonStyle())

                        Button {
                            UIPasteboard.general.string = request.prompt
                            copiedPrompt = true
                            if let url = URL(string: "https://claude.ai/new") {
                                openURL(url)
                            }
                        } label: {
                            Label(copiedPrompt ? "Prompt copied" : "Copy and open Claude", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AgentSecondaryButtonStyle())

                        DisclosureGroup {
                            Text(request.prompt)
                                .font(.agentSubtext)
                                .foregroundStyle(Color.agentSecondary)
                                .textSelection(.enabled)
                                .padding(.top, AgentSpacing.x3)
                        } label: {
                            Text("Review shared context")
                                .font(.agentBody)
                                .foregroundStyle(Color.agentText)
                        }
                    }

                    VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                        SectionRuleHeader(title: "Bring it back")

                        Text("Copy Claude’s answer, return here, and paste it below. Nothing is added until you choose Add response.")
                            .font(.agentBody)
                            .foregroundStyle(Color.agentSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Spacer()
                            Button {
                                response = UIPasteboard.general.string ?? ""
                            } label: {
                                Label("Paste response", systemImage: "doc.on.clipboard")
                            }
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentText)
                        }

                        ZStack(alignment: .topLeading) {
                            if response.isEmpty {
                                Text("Claude’s response")
                                    .font(.agentBody)
                                    .foregroundStyle(Color.agentSecondary)
                                    .padding(.horizontal, AgentSpacing.x4)
                                    .padding(.vertical, AgentSpacing.x3)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $response)
                                .font(.agentBody)
                                .foregroundStyle(Color.agentText)
                                .scrollContentBackground(.hidden)
                                .focused($responseIsFocused)
                                .padding(AgentSpacing.x3)
                                .frame(minHeight: 180)
                        }
                        .background(Color.agentSurface)
                        .clipShape(.rect(cornerRadius: AgentRadius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: AgentRadius.control)
                                .stroke(Color.agentBorder, lineWidth: 1)
                        }

                        Button {
                            onImport(response)
                            dismiss()
                        } label: {
                            Text("Add response")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AgentPrimaryButtonStyle())
                        .disabled(response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Text("Your Claude login and subscription credentials stay with Anthropic. agent.cy receives only the response you explicitly add.")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x8)
                .padding(.bottom, AgentSpacing.x16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.agentCanvas)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
                if responseIsFocused {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") {
                            responseIsFocused = false
                        }
                        .labelStyle(.iconOnly)
                    }
                }
            }
        }
        .agentKeyboardDismissal()
    }
}

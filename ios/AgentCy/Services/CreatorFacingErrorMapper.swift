import Foundation

struct CreatorErrorPresentation: Equatable, Sendable {
    let message: String
    let canRetry: Bool
    let requiresUpgrade: Bool
}

enum CreatorFacingErrorMapper {
    static let postNotFound = "Post not found. It may have been moved or deleted."

    static func presentation(for error: Error, action: String? = nil) -> CreatorErrorPresentation {
        if let reminder = error as? ReminderServiceError {
            switch reminder {
            case .permissionDenied:
                return .init(
                    message: "Notifications are turned off for agent.cy in iPhone Settings.",
                    canRetry: false,
                    requiresUpgrade: false
                )
            case .reminderDatePassed:
                return .init(
                    message: "Choose a reminder time that has not passed.",
                    canRetry: false,
                    requiresUpgrade: false
                )
            }
        }

        if let wire = error as? AIWireError {
            return aiPresentation(for: wire)
        }

        if let api = error as? AgentCyAPIError {
            switch api {
            case .server(let wire):
                return aiPresentation(for: wire)
            case .payloadTooLarge:
                return .init(
                    message: "This request includes too much at once. Remove anything unrelated and try again.",
                    canRetry: true,
                    requiresUpgrade: false
                )
            case .missingCredential:
                return .init(
                    message: "Cy is not connected yet. Open Claude & Codex in Settings to finish setup.",
                    canRetry: false,
                    requiresUpgrade: false
                )
            case .invalidRequest:
                return .init(message: missingFieldMessage(from: error), canRetry: false, requiresUpgrade: false)
            case .http, .invalidStream:
                return cyUnavailable
            }
        }

        if let creative = error as? CreativeServiceError {
            switch creative {
            case .missingInput:
                return .init(
                    message: "Add a little more detail so Cy has something useful to work with.",
                    canRetry: false,
                    requiresUpgrade: false
                )
            case .dialogueLimit:
                return .init(
                    message: "You’ve reached eight turns. Build the post now or keep editing it yourself.",
                    canRetry: false,
                    requiresUpgrade: false
                )
            case .invalidCreatorContext:
                return .init(message: missingFieldMessage(from: error), canRetry: false, requiresUpgrade: false)
            case .invalidLiveResponse, .unsupportedOperation:
                return cyUnavailable
            }
        }

        if let action, !action.isEmpty {
            return .init(
                message: "\(action) couldn’t be completed. Your work is saved. Try again.",
                canRetry: true,
                requiresUpgrade: false
            )
        }

        return .init(
            message: "Something went wrong. Your work is saved. Try again.",
            canRetry: true,
            requiresUpgrade: false
        )
    }

    private static var cyUnavailable: CreatorErrorPresentation {
        .init(
            message: "Cy is unavailable right now. Your work is saved.",
            canRetry: true,
            requiresUpgrade: false
        )
    }

    private static func aiPresentation(for error: AIWireError) -> CreatorErrorPresentation {
        if error.requiresSubscriptionUpgrade {
            return .init(
                message: "Your included Cy access has been used. Upgrade to Pro to keep creating with Cy.",
                canRetry: false,
                requiresUpgrade: true
            )
        }

        switch error.code {
        case .invalidInput:
            return .init(
                message: validationMessage(for: error),
                canRetry: false,
                requiresUpgrade: false
            )
        case .rateLimited, .upstreamUnavailable, .timeout, .usageLimit, .generationInvalid, .maxTokens:
            return cyUnavailable
        case .cancelled:
            return .init(message: "Nothing changed.", canRetry: false, requiresUpgrade: false)
        case .installationInvalid:
            return .init(
                message: "Cy needs to be connected again in Settings.",
                canRetry: false,
                requiresUpgrade: false
            )
        case .payloadTooLarge:
            return .init(
                message: "This request includes too much at once. Remove anything unrelated and try again.",
                canRetry: true,
                requiresUpgrade: false
            )
        case .entitlementRequired, .quotaExceeded:
            return .init(
                message: "Cy is unavailable right now. Your work is saved.",
                canRetry: false,
                requiresUpgrade: false
            )
        case .refusal:
            return .init(
                message: "Cy can’t help with that request. Try a different direction.",
                canRetry: false,
                requiresUpgrade: false
            )
        case .conflict:
            return .init(
                message: "This post changed while Cy was working. Open it again to use the latest version.",
                canRetry: false,
                requiresUpgrade: false
            )
        }
    }

    private static func validationMessage(for error: AIWireError) -> String {
        guard let issue = error.fieldIssues?.first else {
            return "Add the missing post details to continue."
        }
        let field = issue.path.compactMap { component -> String? in
            guard case .key(let key) = component else { return nil }
            return key
        }.last
        guard let field else { return "Add the missing post details to continue." }
        return "Add \(humanized(field)) to continue."
    }

    private static func missingFieldMessage(from error: Error) -> String {
        let lowered = String(describing: error).lowercased()
        let known = ["title", "pillar", "platform", "format", "hook", "caption", "goal"]
        if let field = known.first(where: lowered.contains) {
            return "Add \(field) to continue."
        }
        return "Add the missing details to continue."
    }

    private static func humanized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "Id", with: "")
            .replacingOccurrences(of: "ID", with: "")
            .lowercased()
    }
}

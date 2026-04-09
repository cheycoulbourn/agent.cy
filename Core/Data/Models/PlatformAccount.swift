import Foundation
import SwiftData

@Model
final class PlatformAccount {
    var platform: SocialPlatform
    var handle: String
    var isConnected: Bool
    var followerCount: Int?

    var createdAt: Date

    @Relationship(inverse: \CreatorProfile.platformAccounts) var profile: CreatorProfile?

    init(platform: SocialPlatform, handle: String = "") {
        self.platform = platform
        self.handle = handle
        self.isConnected = false
        self.createdAt = .now
    }
}

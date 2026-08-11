import Foundation

/// Builds lookup tables without assuming SwiftData has already reconciled
/// duplicate domain IDs imported from another CloudKit-backed device.
enum DuplicateSafeIndex {
    static func firstValues<Key: Hashable, Value>(
        _ pairs: [(Key, Value)]
    ) -> [Key: Value] {
        Dictionary(
            pairs,
            uniquingKeysWith: { current, _ in current }
        )
    }
}

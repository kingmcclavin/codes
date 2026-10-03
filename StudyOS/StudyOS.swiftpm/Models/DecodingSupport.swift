import Foundation

// Saved data must keep loading as StudyOS grows. Every model decodes its
// fields with `decode(_:forKey:default:)`, so a field added in a later
// version simply takes its default when an older file is opened.

extension KeyedDecodingContainer {
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: @autoclosure () -> T) throws -> T {
        try decodeIfPresent(type, forKey: key) ?? defaultValue()
    }
}

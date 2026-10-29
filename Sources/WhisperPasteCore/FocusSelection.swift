import Foundation

/// Only external focus is remembered. A lookup from an old app/process or an
/// older tab poll must not replace the current selection. Nothing is persisted.
public struct FocusSelection {
    public struct Lookup {
        fileprivate let id: UUID
        public let application: TerminalDestination
    }
    public private(set) var application: TerminalDestination?
    public private(set) var destination: TerminalDestination?
    private var lookupID: UUID?

    public init() {}

    @discardableResult
    public mutating func observe(_ candidate: TerminalDestination?, isOwnApplication: Bool = false) -> Bool {
        if isOwnApplication { return false }
        if let candidate, let application, candidate.isSameApplication(as: application) { return false }
        if candidate == nil && application == nil { return false }
        application = candidate; destination = nil; lookupID = nil
        return true
    }

    public mutating func beginLookup() -> Lookup? {
        guard let application else { return nil }
        let id = UUID(); lookupID = id
        return Lookup(id: id, application: application)
    }

    @discardableResult
    public mutating func resolve(_ result: TerminalDestination?, for lookup: Lookup) -> Bool {
        guard lookupID == lookup.id, let application,
              application.isSameApplication(as: lookup.application),
              result == nil || result!.isSameApplication(as: application) else { return false }
        lookupID = nil; destination = result
        return true
    }
}

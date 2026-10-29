import Foundation

/// Display language is independent of the Whisper recognition language.
public enum InterfaceLanguage: String, CaseIterable {
    case korean = "ko", english = "en"

    public var name: String { self == .korean ? "한국어" : "English" }
    public var tutorialResource: String { "TUTORIAL.\(rawValue)" }

    public static func saved(in defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: "interfaceLanguage").flatMap(Self.init(rawValue:)) ?? .korean
    }

    public func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: "interfaceLanguage")
    }
}

public protocol AppLocalizedError: LocalizedError {
    var message: AppText { get }
}

extension AppLocalizedError {
    public var errorDescription: String? { message.text }
}

/// Keep messages unresolved so changing language also updates an existing status
/// or error. Literal arguments (transcripts, window titles, diagnostics) stay intact.
public struct AppText: LocalizedError, ExpressibleByStringLiteral {
    private static let bundles: [InterfaceLanguage: Bundle] = {
        let resources = resourceBundle(in: .main)
        return Dictionary(uniqueKeysWithValues: InterfaceLanguage.allCases.map { language in
            let path = resources.path(forResource: language.rawValue, ofType: "lproj")
            return (language, path.flatMap(Bundle.init(path:)) ?? resources)
        })
    }()

    // SwiftPM's generated accessor looks beside the executable or in the build
    // checkout. Installed .app bundles keep resources under Contents/Resources.
    static func resourceBundle(in application: Bundle) -> Bundle {
        if let url = application.url(forResource: "WhisperPaste_WhisperPasteCore", withExtension: "bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return .module
    }

    private let key: String
    private let arguments: [AppText]
    private let isLiteral: Bool

    public init(_ key: String, _ arguments: AppText...) {
        self.key = key; self.arguments = arguments; isLiteral = false
    }

    public init(stringLiteral value: String) { self.init(value) }

    private init(literal: String) {
        key = literal; arguments = []; isLiteral = true
    }

    public static func literal(_ value: String) -> Self { Self(literal: value) }

    public static func describing(_ error: Error) -> Self {
        if let message = error as? Self { return message }
        if let error = error as? AppLocalizedError { return error.message }
        return .literal(error.localizedDescription)
    }

    public var text: String { text(in: .saved()) }
    public var errorDescription: String? { text }

    public func text(in language: InterfaceLanguage) -> String {
        guard !isLiteral else { return key }
        let template = Self.bundles[language]!.localizedString(forKey: key, value: key, table: nil)
        // Replace only template placeholders, never placeholder-like user content.
        return template.components(separatedBy: "{").enumerated().map { offset, part in
            guard offset > 0 else { return part }
            guard let end = part.firstIndex(of: "}"),
                  let index = Int(part[..<end]), arguments.indices.contains(index) else { return "{" + part }
            return arguments[index].text(in: language) + part[part.index(after: end)...]
        }.joined()
    }
}

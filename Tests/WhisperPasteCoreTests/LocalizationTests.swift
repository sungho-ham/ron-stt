import XCTest
@testable import WhisperPasteCore

final class LocalizationTests: XCTestCase {
    func testInterfaceLanguagePersistsIndependentlyOfRecognitionLanguage() throws {
        let suite = "WhisperPaste.LocalizationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("ja", forKey: "language")
        XCTAssertEqual(InterfaceLanguage.saved(in: defaults), .korean)
        InterfaceLanguage.english.save(in: defaults)
        XCTAssertEqual(InterfaceLanguage.saved(in: try XCTUnwrap(UserDefaults(suiteName: suite))), .english)
        XCTAssertEqual(defaults.string(forKey: "language"), "ja")
        InterfaceLanguage.korean.save(in: defaults)
        XCTAssertEqual(InterfaceLanguage.saved(in: defaults), .korean)
        defaults.set("invalid", forKey: "interfaceLanguage")
        XCTAssertEqual(InterfaceLanguage.saved(in: defaults), .korean)
    }

    func testStoredStatusAndNestedDetailsCanBeRenderedInEitherLanguage() {
        let status = AppText("● 녹음 중 {0}초 / 최대 5분 · {1} · {2}\n{3}",
                             .literal("12"), .literal("Small"), "입력 감지", "종료하면 전체 내용을 인식합니다.")
        XCTAssertEqual(status.text(in: .korean), "● 녹음 중 12초 / 최대 5분 · Small · 입력 감지\n종료하면 전체 내용을 인식합니다.")
        XCTAssertEqual(status.text(in: .english), "● Recording 12s / 5 min maximum · Small · Input detected\nThe entire recording will be transcribed when you stop.")
        XCTAssertEqual(status.text(in: .korean), "● 녹음 중 12초 / 최대 5분 · Small · 입력 감지\n종료하면 전체 내용을 인식합니다.")
    }

    func testLiteralContentIsNeverTranslatedOrUsedAsAFormatString() {
        let transcript = "현재 창 {1} 100% 안녕하세요 English 日本語"
        let message = AppText("{0}\n{1}", .literal(transcript), "복사")
        XCTAssertEqual(message.text(in: .english), transcript + "\nCopy")
        XCTAssertEqual(message.text(in: .korean), transcript + "\n복사")
        XCTAssertEqual(AppText.literal(transcript).text(in: .english), transcript)
    }

    func testCapturedErrorsRemainLocalizableWithoutLosingDiagnostics() {
        let message = AppText.describing(TerminalBridgeError.missingTarget)
        XCTAssertTrue(message.text(in: .korean).contains("내용을 보존했습니다"))
        XCTAssertTrue(message.text(in: .english).contains("Your text is preserved"))
        let input = AppText.describing(ApplicationInput.InputError.accessibility)
        XCTAssertTrue(input.text(in: .english).contains("Accessibility permission"))
        let timeout = AppText.describing(TranscriptionError.timedOut)
        XCTAssertTrue(timeout.text(in: .english).contains("Transcription timed out"))
        let detail = "engine diagnostic: 현재 창 {0} 100%"
        XCTAssertEqual(AppText.describing(TranscriptionError.failed(detail)).text(in: .english), detail)
    }

    func testTutorialSelectionFollowsOnlyTheInterfaceLanguage() {
        XCTAssertEqual(InterfaceLanguage.english.tutorialResource, "TUTORIAL.en")
        XCTAssertEqual(InterfaceLanguage.korean.tutorialResource, "TUTORIAL.ko")
    }

    func testCatalogsContainTheSameKeysAndFormattingArguments() throws {
        let resources = AppText.resourceBundle(in: .main)
        func catalog(_ language: InterfaceLanguage) throws -> [String: String] {
            let url = try XCTUnwrap(resources.url(forResource: "Localizable", withExtension: "strings",
                                                 subdirectory: nil, localization: language.rawValue))
            return try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
        }
        let korean = try catalog(.korean), english = try catalog(.english)
        XCTAssertFalse(korean.isEmpty)
        XCTAssertEqual(Set(korean.keys), Set(english.keys))
        let placeholder = try NSRegularExpression(pattern: #"\{\d+\}"#)
        func placeholders(_ text: String) -> [String] {
            placeholder.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
                (text as NSString).substring(with: $0.range)
            }.sorted()
        }
        for (key, translation) in english {
            XCTAssertEqual(placeholders(key), placeholders(translation), "Mismatched arguments: \(key)")
            XCTAssertEqual(korean[key], key)
        }
    }

    func testInstalledAppLoadsItsOwnResourcesWithoutTheBuildCheckout() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("whisper-paste-localization-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appendingPathComponent("ron.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: String] = ["CFBundleIdentifier": "test.whisper-paste.localization",
                                     "CFBundleExecutable": "ron", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let packaged = resources.appendingPathComponent("WhisperPaste_WhisperPasteCore.bundle", isDirectory: true)
        try FileManager.default.copyItem(at: AppText.resourceBundle(in: .main).bundleURL, to: packaged)
        let installed = try XCTUnwrap(Bundle(url: app))
        let loaded = AppText.resourceBundle(in: installed)
        XCTAssertEqual(loaded.bundleURL, packaged)
        let path = try XCTUnwrap(loaded.path(forResource: "en", ofType: "lproj"))
        let english = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(english.localizedString(forKey: "시작", value: nil, table: nil), "Start")
    }
}

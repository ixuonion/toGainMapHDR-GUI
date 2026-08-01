import Foundation
import Testing
@testable import GainMapHDRApp

@Suite("Conversion command")
struct ConversionCommandTests {
    @Test("Loads localized resources")
    func loadsLocalizedResources() {
        #expect(L10n.text("ready") != "ready")
    }

    @Test("Builds backend command from README contract")
    func buildsSingleFileCommand() throws {
        let input = ImageInput(url: URL(fileURLWithPath: "/Users/example/In/test.tiff"))
        var settings = ConversionSettings()
        settings.destinationChoice = .custom
        settings.customDestination = URL(fileURLWithPath: "/Users/example/Out")
        settings.quality = 95
        settings.colorSpace = .rec2020
        settings.bitDepth = .ten
        settings.outputMode = .appleGainMap
        settings.subsampleGainMap = true
        settings.monochromeGainMap = true

        let request = ConversionRequest(inputs: [input], settings: settings)
        let command = try #require(request.command(for: input))

        #expect(command.executable == "toGainMapHDR")
        #expect(command.arguments == [
            "/Users/example/In/test.tiff",
            "/Users/example/Out",
            "-q", "0.95",
            "-r", "3.0",
            "-R", "6.0",
            "-c", "rec2020",
            "-d", "10",
            "-t", "-HDR",
            "-g",
            "-H", "2",
            "-m"
        ])
    }

    @Test("Representative command uses first input only")
    func representativeCommandUsesFirstInput() throws {
        let first = ImageInput(url: URL(fileURLWithPath: "/tmp/first.png"))
        let second = ImageInput(url: URL(fileURLWithPath: "/tmp/second.png"))
        var settings = ConversionSettings()
        settings.destinationChoice = .custom
        settings.customDestination = URL(fileURLWithPath: "/tmp/out")

        let command = try #require(ConversionRequest(inputs: [first, second], settings: settings).representativeCommand())

        #expect(command.arguments.first == "/tmp/first.png")
        #expect(!command.arguments.contains("/tmp/second.png"))
    }

    @Test("Settings clamp user-entered numeric fields")
    func settingsClampNumericFields() {
        var settings = ConversionSettings()
        settings.quality = 120
        settings.concurrency = 999
        settings.toneMappingRatio = 0.1
        settings.maxHeadroom = 500
        settings.clampValues()

        #expect(settings.quality == 100)
        #expect(settings.concurrency <= ProcessInfo.processInfo.processorCount)
        #expect(settings.toneMappingRatio == 1)
        #expect(settings.maxHeadroom == 100)
    }
}

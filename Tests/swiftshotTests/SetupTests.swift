import XCTest
@testable import swiftshot

final class SetupTests: XCTestCase {
    func testKnownRegionsToLanguages() {
        let pbx = """
        		developmentRegion = en;
        		hasScannedForEncodings = 0;
        		knownRegions = (
        			Base,
        			ar,
        			de,
        			en,
        			"zh-Hans",
        		);
        """
        XCTAssertEqual(Setup.knownRegions(pbx), ["en", "Base", "ar", "de", "zh-Hans"], "development region first")
        XCTAssertEqual(Setup.languages(fromRegions: Setup.knownRegions(pbx)), ["en-US", "ar-SA", "de-DE", "zh-Hans"])
        XCTAssertEqual(Setup.knownRegions("knownRegions = (en, Base, );"), ["en", "Base"])
        XCTAssertEqual(Setup.languages(fromRegions: ["Base"]), ["en-US"])
        XCTAssertEqual(Setup.languages(fromRegions: ["en", "Base", "en", "fr"]), ["en-US", "fr-FR"])
    }

    func testCatalogLanguages() {
        let catalog = #"{"sourceLanguage": "en", "strings": {"Hi": {"localizations": {"de": {}, "sk": {}}}}, "version": "1.0"}"#
        XCTAssertEqual(Setup.catalogLanguages(Data(catalog.utf8)), ["en", "de", "sk"])
    }

    func testSchemeClassification() {
        let app = ["PRODUCT_TYPE": "com.apple.product-type.application", "WRAPPER_EXTENSION": "app", "PLATFORM_NAME": "iphoneos", "TARGETED_DEVICE_FAMILY": "1,2"]
        let tests = ["PRODUCT_TYPE": "com.apple.product-type.bundle.ui-testing", "WRAPPER_EXTENSION": "xctest", "PLATFORM_NAME": "iphoneos"]
        let framework = ["PRODUCT_TYPE": "com.apple.product-type.framework", "WRAPPER_EXTENSION": "framework", "PLATFORM_NAME": "iphoneos"]
        let watch = ["PRODUCT_TYPE": "com.apple.product-type.application", "WRAPPER_EXTENSION": "app",
                     "SDKROOT": "/Applications/Xcode.app/Contents/Developer/Platforms/WatchOS.platform/Developer/SDKs/WatchOS27.0.sdk", "TARGETED_DEVICE_FAMILY": "4"]
        var phoneOnly = app; phoneOnly["TARGETED_DEVICE_FAMILY"] = "1"
        XCTAssertEqual(Setup.classify([app, tests]), .iosApp(iPad: true))
        XCTAssertEqual(Setup.classify([phoneOnly]), .iosApp(iPad: false))
        XCTAssertEqual(Setup.classify([watch]), .watchApp)
        XCTAssertEqual(Setup.classify([watch, app]), .iosApp(iPad: true), "an iOS app embedding its watch app is the iOS app")
        XCTAssertNil(Setup.classify([tests, framework]))
        XCTAssertEqual(Setup.candidateSchemes(["App", "AppTests", "AppUITests", "Pods-App", "Watch"]), ["App", "Watch"])
    }

    func testProjectPick() throws {
        XCTAssertNil(try Setup.pickProject(["README.md", "Sources"]))
        XCTAssertEqual(try Setup.pickProject(["App.xcodeproj"])?.project, "App.xcodeproj")
        // CocoaPods: the workspace wraps the app project; Pods.xcodeproj never counts.
        XCTAssertEqual(try Setup.pickProject(["App.xcodeproj", "App.xcworkspace", "Pods"])?.workspace, "App.xcworkspace")
        XCTAssertEqual(try Setup.pickProject(["Pods.xcodeproj", "App.xcodeproj"])?.project, "App.xcodeproj")
        XCTAssertThrowsError(try Setup.pickProject(["A.xcodeproj", "B.xcodeproj"]))
        XCTAssertEqual(Setup.workspaceProjectRefs(#"<FileRef location = "group:App.xcodeproj"></FileRef><FileRef location = "group:Pods/Pods.xcodeproj">"#),
                       ["App.xcodeproj", "Pods/Pods.xcodeproj"])
    }

    func testDeviceSelection() {
        func type(_ name: String, _ family: String, min: String = "17.0.0", max: String = "65535.255.255") -> SimDeviceType {
            SimDeviceType(identifier: "t.\(name)", name: name, productFamily: family, bundlePath: "/nonexistent",
                          modelIdentifier: nil, minRuntimeVersionString: min, maxRuntimeVersionString: max)
        }
        let types = [
            type("iPhone 17 Pro Max", "iPhone", min: "26.0.0"), type("iPhone 18 Pro Max", "iPhone", min: "27.0.0"),
            type("iPhone 18 Pro", "iPhone", min: "27.0.0"), type("iPhone 9 Pro Max", "iPhone"),
            type("iPad Pro 13-inch (M4)", "iPad"), type("iPad Pro 13-inch (M5)", "iPad", min: "26.0.0"),
            type("iPad Pro 13-inch (M5) (16GB)", "iPad", min: "26.0.0"), type("iPad Pro 11-inch (M5)", "iPad", min: "26.0.0"),
            type("Apple Watch Ultra (49mm)", "Apple Watch", min: "9.0.0", max: "26.99.0"),
            type("Apple Watch Ultra 3 (49mm)", "Apple Watch", min: "26.0.0"), type("Apple Watch Ultra 4 (49mm)", "Apple Watch", min: "27.0.0"),
        ]
        XCTAssertEqual(Setup.pickDevices(types, iosRuntime: "27.1", watchRuntime: "27.0", iPhone: true, iPad: true, watch: true),
                       ["iPhone 18 Pro Max", "iPad Pro 13-inch (M5)", "Apple Watch Ultra 4 (49mm)"])
        // Older runtimes: only the device types they can run.
        XCTAssertEqual(Setup.pickDevices(types, iosRuntime: "26.5", watchRuntime: "26.0", iPhone: true, iPad: false, watch: true),
                       ["iPhone 17 Pro Max", "Apple Watch Ultra 3 (49mm)"])
        XCTAssertEqual(Setup.pickDevices(types, iosRuntime: "18.0", watchRuntime: "10.0", iPhone: false, iPad: true, watch: true),
                       ["iPad Pro 13-inch (M4)", "Apple Watch Ultra (49mm)"])
        XCTAssertTrue(Setup.versionLess("26.5", "27.0.0"))
        XCTAssertFalse(Setup.versionLess("27.0", "27.0.0"))
    }

    func testInitCommandIgnoresExistingConfig() throws {
        let o = try Options.parse(["auto-setup", "--force", "--scheme", "App"])
        XCTAssertEqual(o.command, "init")
        XCTAssertTrue(o.force)
        XCTAssertEqual(o.scheme, "App")
    }
}

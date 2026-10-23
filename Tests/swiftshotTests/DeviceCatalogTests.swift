import XCTest
@testable import swiftshot

final class DeviceCatalogTests: XCTestCase {
    /// A CoreSimulator device-type bundle with just a capabilities.plist.
    private func deviceType(name: String, family: String = "iPhone", capabilities: [String: Any]) throws -> SimDeviceType {
        let bundle = FileManager.default.temporaryDirectory.appendingPathComponent("swiftshot-\(UUID()).simdevicetype")
        let resources = bundle.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: ["capabilities": capabilities], format: .xml, options: 0)
        try data.write(to: resources.appendingPathComponent("capabilities.plist"))
        return SimDeviceType(identifier: "test.\(name)", name: name, productFamily: family, bundlePath: bundle.path,
                             modelIdentifier: nil, minRuntimeVersionString: nil, maxRuntimeVersionString: nil)
    }

    func testScreenFromDisplaysArray() throws {
        let type = try deviceType(name: "Test Phone", capabilities: [
            "DeviceCornerRadius": 62,
            "displays": [["deviceName": "primary", "width": 1206, "height": 2622, "scale": 3, "hdpi": 460, "cornerRadiusUL": 62]],
        ])
        let s = try XCTUnwrap(DeviceCatalog.screen(of: type))
        XCTAssertEqual(s.width, 402); XCTAssertEqual(s.height, 874); XCTAssertEqual(s.scale, 3)
        XCTAssertEqual(s.corner, 62); XCTAssertEqual(s.pitch, 460)
    }

    /// UIScreen reports DeviceCornerRadius; a panel's per-corner radii can differ (iPhone Duo:
    /// 8 on the hinge side, 59 outside) and must not win.
    func testCornerRadiusPrefersDeviceCornerRadius() throws {
        let type = try deviceType(name: "Fold", capabilities: [
            "DeviceCornerRadius": 59,
            "displays": [["deviceName": "primary", "width": 1398, "height": 2034, "scale": 3, "cornerRadiusUL": 8, "cornerRadiusUR": 59]],
        ])
        XCTAssertEqual(DeviceCatalog.screen(of: type)?.corner, 59)
    }

    /// The per-corner radii travel separately (scene settings report them; sheets follow them),
    /// in UIKit's order: top left, bottom left, bottom right, top right.
    func testPerCornerRadiiWhenTheyDiffer() throws {
        let duo = try deviceType(name: "iPhone Duo", capabilities: [
            "DeviceCornerRadius": 59,
            "displays": [["deviceName": "primary", "width": 1398, "height": 2034, "scale": 3,
                          "cornerRadiusUL": 8, "cornerRadiusLL": 8, "cornerRadiusLR": 59, "cornerRadiusUR": 59]],
        ])
        XCTAssertEqual(DeviceCatalog.screen(of: duo)?.radii, [8, 8, 59, 59])
        XCTAssertEqual(try XCTUnwrap(DeviceCatalog.profile(for: duo, runtime: "27.1", cache: [:])).0.cornerRadii, [8, 8, 59, 59])
        let phone = try deviceType(name: "Test Phone", capabilities: [
            "DeviceCornerRadius": 62,
            "displays": [["deviceName": "primary", "width": 1206, "height": 2622, "scale": 3,
                          "cornerRadiusUL": 62, "cornerRadiusLL": 62, "cornerRadiusLR": 62, "cornerRadiusUR": 62]],
        ])
        XCTAssertNil(DeviceCatalog.screen(of: phone)?.radii, "uniform corners need no override")
    }

    func testLegacyScreenDimensions() throws {
        let type = try deviceType(name: "Old Phone", capabilities: [
            "ScreenDimensionsCapability": ["main-screen-width": 750, "main-screen-height": 1334, "main-screen-scale": 2],
        ])
        let s = try XCTUnwrap(DeviceCatalog.screen(of: type))
        XCTAssertEqual(s.width, 375); XCTAssertEqual(s.height, 667)
    }

    func testBuiltInProfileCarriesDisplayData() throws {
        let type = try deviceType(name: "iPhone Duo", capabilities: [
            "DeviceCornerRadius": 59,
            "displays": [["deviceName": "primary", "width": 1398, "height": 2034, "scale": 3]],
        ])
        let (profile, source) = try XCTUnwrap(DeviceCatalog.profile(for: type, runtime: "27.1", cache: [:]))
        XCTAssertEqual(source, "built-in")
        XCTAssertEqual(profile.safeArea, Insets(top: 0, left: 0, bottom: 34, right: 84), "status bar rail on the right")
        let display = try XCTUnwrap(profile.display)
        XCTAssertEqual(display.statusBarAxis, 1)
        XCTAssertEqual(display.verticalBarAllowed, 1)
        XCTAssertEqual(display.cornerInsets?.count, 8)
        XCTAssertEqual(display.barPosition?.count, 8)
    }

    /// A device missing from the safe-area table but present in the measured display table uses
    /// the measured safe area (iPhone 14 Pro: 59 pt, not the heuristic's 62 — checked against a
    /// real iPhone 14 Pro).
    func testDisplayTableSafeAreaBeatsHeuristic() throws {
        let type = try deviceType(name: "iPhone 14 Pro", capabilities: [
            "DeviceCornerRadius": 55,
            "displays": [["deviceName": "primary", "width": 1179, "height": 2556, "scale": 3]],
        ])
        let (profile, source) = try XCTUnwrap(DeviceCatalog.profile(for: type, runtime: "26.5", cache: [:]))
        XCTAssertEqual(source, "built-in display")
        XCTAssertEqual(profile.safeArea, Insets(top: 59, left: 0, bottom: 34, right: 0))
        XCTAssertEqual(profile.landscapeSafeArea, Insets(top: 0, left: 59, bottom: 21, right: 59))
    }

    func testHeuristicForUnknownDevice() throws {
        let type = try deviceType(name: "iPhone 99 Ultra", capabilities: [
            "DeviceCornerRadius": 62,
            "displays": [["deviceName": "primary", "width": 1320, "height": 2868, "scale": 3]],
        ])
        let (profile, source) = try XCTUnwrap(DeviceCatalog.profile(for: type, runtime: "27.0", cache: [:]))
        XCTAssertEqual(source, "heuristic")
        XCTAssertEqual(profile.safeArea.top, 62)
        XCTAssertEqual(profile.safeArea.bottom, 34)
    }

    func testCalibrationCacheWins() throws {
        let type = try deviceType(name: "iPhone 17", capabilities: ["displays": [["deviceName": "primary", "width": 1206, "height": 2622, "scale": 3]]])
        let measured = DeviceProfile(name: "iPhone 17", idiom: "phone", width: 402, height: 874, scale: 3,
                                     safeArea: Insets(top: 1, left: 2, bottom: 3, right: 4), landscapeSafeArea: .zero, cornerRadius: 55)
        let (profile, source) = try XCTUnwrap(DeviceCatalog.profile(for: type, runtime: "27.0", cache: ["iPhone 17@27.0": measured]))
        XCTAssertEqual(source, "calibrated")
        XCTAssertEqual(profile.safeArea, Insets(top: 1, left: 2, bottom: 3, right: 4))
    }

    /// Calibration files written before the status bar / scene fields existed still load.
    func testDisplayInfoDecodesOlderFiles() throws {
        let json = #"{"safeAreaPortrait":{"top":62,"left":0,"bottom":34,"right":0},"safeAreaPortraitUpsideDown":{"top":0,"left":0,"bottom":0,"right":0},"safeAreaLandscapeLeft":{"top":0,"left":0,"bottom":0,"right":0},"safeAreaLandscapeRight":{"top":0,"left":0,"bottom":0,"right":0},"periphery":{"top":0,"left":0,"bottom":0,"right":0},"homeAffordanceOverlayAllowance":21,"systemMinimumMargin":0,"artworkSubtype":0,"screenPeriphery":{"top":0,"left":0,"bottom":0,"right":0},"screenDisplayPeriphery":{"top":0,"left":0,"bottom":0,"right":0}}"#
        let d = try JSONDecoder().decode(DisplayInfo.self, from: Data(json.utf8))
        XCTAssertNil(d.statusBarAxis)
        XCTAssertNil(d.barPosition)
        XCTAssertEqual(d.safeAreaPortrait.top, 62)
    }

    /// The generated BuiltInDisplays.swift keeps every field, so regenerating it on a new Xcode
    /// loses nothing.
    func testDisplayTableSourceRoundTripsAllFields() throws {
        var duo = try XCTUnwrap(BuiltInDisplays.table["iPhone Duo"])
        duo.statusBarHeight = 2
        let profile = DeviceProfile(name: "iPhone Duo", idiom: "phone", width: 466, height: 678, scale: 3,
                                    safeArea: .zero, landscapeSafeArea: .zero, cornerRadius: 59, display: duo)
        let source = DeviceCatalog.displayTableSource(["iPhone Duo@27.1": profile], existing: [:], existingSizes: [:], existingSafeAreas: [:], header: "// test")
        for field in ["statusBarAxis: 1", "statusBarFrameHeight: 2.0", "statusBarHeight: 2.0", "verticalBarAllowed: 1", "verticalBarEdge: 2", "cornerInsets: [", "barPosition: ["] {
            XCTAssertTrue(source.contains(field), "missing \(field)")
        }
    }

    func testEveryBuiltInPhoneHasConsistentSafeAreas() {
        for (name, (portrait, _)) in BuiltInDevices.table where name.hasPrefix("iPhone") {
            XCTAssertGreaterThanOrEqual(portrait.top + portrait.right, 20, "\(name): a phone has a status bar somewhere")
        }
    }
}

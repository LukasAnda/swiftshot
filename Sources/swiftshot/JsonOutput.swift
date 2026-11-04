import Foundation

/// The documents `list --json` and `devices --json` print (docs/wiki/Command-line.md). The Kotlin CLI builds the same shapes.
enum JsonOutput {
    /// `{"previews": [{"name": ...}]}`, in the order given.
    static func list(previews: [String]) -> JSON {
        .object(["previews": .array(previews.map { .object(["name": .string($0)]) })])
    }

    struct Device: Equatable {
        let name: String
        let platform: String
        let width: Double
        let height: Double
        let scale: Double
    }

    /// `{"devices": [{name, platform, width, height, scale}], "runtimes": [...]}`; width and height in points.
    static func devices(_ devices: [Device], runtimes: [String]) -> JSON {
        .object([
            "devices": .array(devices.map {
                .object(["name": .string($0.name), "platform": .string($0.platform), "width": number($0.width), "height": number($0.height), "scale": number($0.scale)])
            }),
            "runtimes": .array(runtimes.map { .string($0) }),
        ])
    }

    private static func number(_ d: Double) -> JSON { d == d.rounded(.towardZero) && abs(d) < 1e15 ? .int(Int64(d)) : .double(d) }
}

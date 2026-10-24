// Finds SwiftUI previews inside the running app without any help from Xcode.
//
// `#Preview { ... }` expands to a struct conforming to `DeveloperToolsSupport.PreviewRegistry`,
// and legacy previews conform to `SwiftUI.PreviewProvider`. The Swift compiler records every
// protocol conformance in the `__TEXT,__swift5_proto` section of the binary, so we walk that
// section in every image that belongs to the app bundle, pick out the two protocols and call
// the type's metadata accessor to get a real metatype we can use from Swift.

import Foundation
import MachO
import SwiftUI
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif
import DeveloperToolsSupport

struct PreviewLayoutSpec {
    enum Kind { case device, sizeThatFits, fixed(CGFloat, CGFloat) }
    var kind: Kind = .device
    var landscape = false
}

struct DiscoveredPreview {
    let name: String
    let fileID: String
    let line: Int
    let layout: PreviewLayoutSpec
    /// Builds the preview body (a SwiftUI view, UIViewController or UIView) fresh each call.
    let body: @MainActor () -> Any
}

// MARK: - Mach-O conformance scan

private func relativeDirect(_ base: UnsafeRawPointer) -> UnsafeRawPointer? {
    let offset = base.loadUnaligned(as: Int32.self)
    return offset == 0 ? nil : base + Int(offset)
}

private func relativeIndirectable(_ base: UnsafeRawPointer) -> UnsafeRawPointer? {
    let offset = base.loadUnaligned(as: Int32.self)
    if offset == 0 { return nil }
    if offset & 1 == 1 {
        return (base + Int(offset & ~1)).load(as: UnsafeRawPointer?.self)
    }
    return base + Int(offset)
}

private func conformingTypes(to protocolNames: Set<String>, inImagesUnder prefix: String) -> [(String, Any.Type)] {
    var found: [(String, Any.Type)] = []
    for index in 0..<_dyld_image_count() {
        guard let cName = _dyld_get_image_name(index),
              String(cString: cName).hasPrefix(prefix),
              let header = _dyld_get_image_header(index) else { continue }
        var size: UInt = 0
        let mh = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
        guard let section = getsectiondata(mh, "__TEXT", "__swift5_proto", &size) else { continue }
        let start = UnsafeRawPointer(section)
        for i in 0..<(Int(size) / 4) {
            // Each entry is a relative pointer to a ProtocolConformanceDescriptor:
            //   protocol (rel. indirectable), typeRef (rel), witnessTable (rel), flags (u32)
            guard let descriptor = relativeDirect(start + i * 4),
                  let proto = relativeIndirectable(descriptor),
                  let protoName = relativeDirect(proto + 8) else { continue }
            let name = String(cString: protoName.assumingMemoryBound(to: CChar.self))
            guard protocolNames.contains(name) else { continue }

            let flags = (descriptor + 12).loadUnaligned(as: UInt32.self)
            let typeDescriptor: UnsafeRawPointer?
            switch (flags >> 3) & 0x7 {
            case 0: typeDescriptor = relativeDirect(descriptor + 4)
            case 1: typeDescriptor = relativeDirect(descriptor + 4).flatMap { $0.load(as: UnsafeRawPointer?.self) }
            default: continue // ObjC class references can't be previews
            }
            guard let typeDescriptor else { continue }
            let typeFlags = typeDescriptor.loadUnaligned(as: UInt32.self)
            if typeFlags & 0x80 != 0 { continue } // generic: needs arguments, skip
            // TypeContextDescriptor: flags, parent, name, accessFunction
            guard let accessor = relativeDirect(typeDescriptor + 12) else { continue }
            typealias MetadataAccessor = @convention(c) (Int) -> UnsafeRawPointer
            let metadata = unsafeBitCast(accessor, to: MetadataAccessor.self)(0)
            found.append((name, unsafeBitCast(metadata, to: Any.Type.self)))
        }
    }
    return found
}

// MARK: - Reflection helpers

private func firstChild(_ value: Any, labeled label: String, depth: Int = 0) -> Any? {
    guard depth < 12 else { return nil }
    for child in Mirror(reflecting: value).children {
        if child.label == label { return child.value }
        if let hit = firstChild(child.value, labeled: label, depth: depth + 1) { return hit }
    }
    return nil
}

private func allChildren(_ value: Any, labeled label: String, depth: Int = 0, into out: inout [Any]) {
    guard depth < 12 else { return }
    for child in Mirror(reflecting: value).children {
        if child.label == label { out.append(child.value) } else {
            allChildren(child.value, labeled: label, depth: depth + 1, into: &out)
        }
    }
}

/// Function type metadata: kind, flags, result type, params...
private func resultType(ofFunctionType type: Any.Type) -> Any.Type {
    let metadata = unsafeBitCast(type, to: UnsafeRawPointer.self)
    return unsafeBitCast((metadata + 16).load(as: UnsafeRawPointer.self), to: Any.Type.self)
}

/// `makeBody` is `@MainActor () -> ViewPreviewBody` where `ViewPreviewBody` is SwiftUI-internal.
/// We open the result type from the function metadata so we can call it without naming it.
@MainActor private func invokeThunk(_ function: Any) -> Any {
    func call<R>(_: R.Type) -> Any { (function as! @MainActor () -> R)() }
    return _openExistential(resultType(ofFunctionType: type(of: function)), do: call)
}

#if os(iOS)
@MainActor func controller(fromBody body: Any) -> UIViewController? {
    if let view = body as? any View { return UIHostingController(rootView: AnyView(view)) }
    if let vc = body as? UIViewController { return vc }
    if let view = body as? UIView {
        let vc = UIViewController()
        view.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
            view.topAnchor.constraint(equalTo: vc.view.topAnchor),
            view.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
        ])
        return vc
    }
    for child in Mirror(reflecting: body).children {
        if let vc = controller(fromBody: child.value) { return vc }
    }
    return nil
}
#endif

/// Finds the SwiftUI view inside a preview body (watchOS rendering).
@MainActor func swiftUIView(fromBody body: Any) -> AnyView? {
    if let view = body as? any View { return AnyView(view) }
    for child in Mirror(reflecting: body).children {
        if let view = swiftUIView(fromBody: child.value) { return view }
    }
    return nil
}

private func layoutSpec(fromTraits traits: Any) -> PreviewLayoutSpec {
    var spec = PreviewLayoutSpec()
    for trait in Mirror(reflecting: traits).children.map(\.value) {
        let typeName = String(describing: type(of: trait))
        guard let value = Mirror(reflecting: trait).children.first(where: { $0.label == "value" })?.value else { continue }
        if typeName.contains("Orientation") {
            spec.landscape = String(describing: value).lowercased().contains("landscape")
        } else if typeName.contains("Layout"), let layout = value as? PreviewLayout {
            switch layout {
            case .sizeThatFits: spec.kind = .sizeThatFits
            case .fixed(let w, let h): spec.kind = .fixed(w, h)
            default: spec.kind = .device
            }
        }
    }
    return spec
}

// MARK: - Public entry

@MainActor
func discoverPreviews() -> [DiscoveredPreview] {
    let bundlePath = Bundle.main.bundlePath
    var previews: [DiscoveredPreview] = []

    for (protocolName, type) in conformingTypes(to: ["PreviewRegistry", "PreviewProvider"], inImagesUnder: bundlePath) {
        if protocolName == "PreviewRegistry", let registry = type as? any PreviewRegistry.Type {
            guard let preview = try? registry.makePreview() else { continue }
            let file = (registry.fileID as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
            let displayName = firstChild(preview, labeled: "displayName").flatMap { $0 as? String }
            let traits = firstChild(preview, labeled: "traits") ?? [Any]()
            var bodies: [Any] = []
            allChildren(preview, labeled: "makeBody", into: &bodies)
            for (i, body) in bodies.enumerated() {
                var name = displayName ?? "\(file)_\(registry.line)"
                if bodies.count > 1 { name += "_\(i + 1)" }
                previews.append(DiscoveredPreview(
                    name: name, fileID: registry.fileID, line: registry.line,
                    layout: layoutSpec(fromTraits: traits),
                    body: { invokeThunk(body) }))
            }
        } else if protocolName == "PreviewProvider", let provider = type as? any PreviewProvider.Type {
            let typeName = String(describing: provider).replacingOccurrences(of: "_Previews", with: "")
            func make<P: PreviewProvider>(_ p: P.Type) -> Any { AnyView(p.previews) }
            previews.append(DiscoveredPreview(
                name: typeName, fileID: typeName, line: 0, layout: PreviewLayoutSpec(),
                body: { make(provider) }))
        }
    }
    // Stable, source-ordered output.
    return previews.sorted { ($0.fileID, $0.line, $0.name) < ($1.fileID, $1.line, $1.name) }
}

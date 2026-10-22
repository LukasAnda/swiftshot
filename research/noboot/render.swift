import Foundation
import UIKit
import SwiftUI

struct Screen: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Today") {
                    ForEach(["Drink water", "Read 20 pages", "Walk 10k steps"], id: \.self) { t in
                        Label(t, systemImage: "checkmark.circle.fill")
                    }
                }
                Toggle("Reminders", isOn: .constant(true))
            }
            .navigationTitle("Habits")
            .toolbar { Button("Add", systemImage: "plus") {} }
            .overlay(alignment: .bottom) {
                Text("Glass").padding().glassEffect().padding(.bottom, 40)
            }
        }
    }
}

import Metal
import ObjectiveC
let t00 = Date()
if ProcessInfo.processInfo.environment["NOBOOT_PATCH_DISPLAYS"] == "1", let cls = NSClassFromString("CADisplay"),
   let m = class_getClassMethod(cls, NSSelectorFromString("displays")) {
    let block: @convention(block) (AnyObject) -> NSArray = { _ in NSArray() }
    method_setImplementation(m, imp_implementationWithBlock(block))
}
if let cls = NSClassFromString("UIScreen") {
    let scale: @convention(block) (AnyObject) -> CGFloat = { _ in 3 }
    let bounds: @convention(block) (AnyObject) -> CGRect = { _ in CGRect(x: 0, y: 0, width: 440, height: 956) }
    let native: @convention(block) (AnyObject) -> CGRect = { _ in CGRect(x: 0, y: 0, width: 1320, height: 2868) }
    for (sel, imp) in [("scale", imp_implementationWithBlock(scale)), ("nativeScale", imp_implementationWithBlock(scale)),
                       ("bounds", imp_implementationWithBlock(bounds)), ("nativeBounds", imp_implementationWithBlock(native))] {
        if let m = class_getInstanceMethod(cls, NSSelectorFromString(sel)) { method_setImplementation(m, imp) }
    }
}
let out = CommandLine.arguments[1]
let mode = CommandLine.arguments[2]
let size = CGSize(width: 440, height: 956)
func save(_ img: UIImage?, _ name: String) {
    guard let data = img?.pngData() else { print("\(name): nil image"); return }
    try! data.write(to: URL(fileURLWithPath: "\(out)/\(name).png")); print("\(name): ok \(img!.size) @\(img!.scale)")
}
let t0 = Date()
MainActor.assumeIsolated {
    switch mode {
    case "imagerenderer":
        let r = ImageRenderer(content: Screen().frame(width: size.width, height: size.height)); r.scale = 3
        save(r.uiImage, "imagerenderer")
    case "layer", "hierarchy", "carenderer":
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        print("screen scale \(UIScreen.main.scale) bounds \(UIScreen.main.bounds) +\(Int(Date().timeIntervalSince(t00)*1000))ms")
        let vc = UIHostingController(rootView: Screen())
        if ProcessInfo.processInfo.environment["NOBOOT_SAFE"] == "1" { vc.additionalSafeAreaInsets = UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0) }
        window.rootViewController = vc
        window.isHidden = false
        window.layoutIfNeeded()
        for _ in 0..<5 { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)); window.layoutIfNeeded() }
        if mode == "carenderer" {
            guard let device = MTLCreateSystemDefaultDevice() else { print("no metal device"); return }
            print("metal: \(device.name)")
            let w = Int(size.width * 3), h = Int(size.height * 3)
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
            let tex = device.makeTexture(descriptor: desc)!
            let queue = device.makeCommandQueue()!
            let renderer = CARenderer(mtlTexture: tex, options: [kCARendererMetalCommandQueue: queue])
            // CARenderer draws the layer tree in pixels: scale the root to 3x.
            let root = CALayer(); root.frame = CGRect(x: 0, y: 0, width: w, height: h)
            root.isGeometryFlipped = false
            window.layer.removeFromSuperlayer()
            root.addSublayer(window.layer)
            window.layer.setAffineTransform(CGAffineTransform(scaleX: 3, y: 3))
            window.layer.position = CGPoint(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
            renderer.layer = root
            renderer.bounds = root.frame
            for i in 0..<3 {
                renderer.beginFrame(atTime: CACurrentMediaTime() + Double(i), timeStamp: nil)
                renderer.addUpdate(renderer.bounds)
                renderer.render()
                renderer.endFrame()
            }
            let cb = queue.makeCommandBuffer()!; cb.commit(); cb.waitUntilCompleted()
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            tex.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            let cs = CGColorSpaceCreateDeviceRGB()
            let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            save(UIImage(cgImage: ctx.makeImage()!), "carenderer")
            return
        }
        let f = UIGraphicsImageRendererFormat(); f.scale = 3
        let img = UIGraphicsImageRenderer(size: size, format: f).image { ctx in
            if mode == "layer" { window.layer.render(in: ctx.cgContext) }
            else { _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        }
        save(img, mode)
    default: break
    }
}
print("took \(Int(Date().timeIntervalSince(t0) * 1000)) ms")

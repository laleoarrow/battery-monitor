import AppKit
import CryptoKit

// Read-only test evidence. This executable creates no application or window.
// It records resources owned by the running OS; none are bundled into Wattson.
private let requiredResourceNames = [
    "battery-outline", "battery-cap", "battery-bolt", "battery-bolt-mask",
]
private let optionalResourceNames = [
    "battery-bolt-large", "battery-bolt-mask-large",
    "battery-plug-large", "battery-plug-mask-large",
]
private let resourceNames = requiredResourceNames + optionalResourceNames

private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func renderedPNG(_ image: NSImage, scale: Int) throws -> Data {
    let width = max(1, Int(ceil(image.size.width * CGFloat(scale))))
    let height = max(1, Int(ceil(image.size.height * CGFloat(scale))))
    guard width <= 4096, height <= 4096,
          let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
          ), let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else { throw NSError(domain: "ArtworkProbe", code: 1) }
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.clear.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
    image.draw(
        in: NSRect(x: 0, y: 0, width: width, height: height),
        from: .zero, operation: .sourceOver, fraction: 1,
        respectFlipped: false, hints: nil
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ArtworkProbe", code: 2)
    }
    return png
}

guard CommandLine.arguments.count == 2 else {
    fputs("usage: probe-system-battery-artwork evidence-directory\n", stderr)
    exit(64)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let bundlePath = "/System/Library/CoreServices/ControlCenter.app"
var result: [String: Any] = [
    "schema": 1,
    "purpose": "Read-only OS-owned battery artwork evidence; no product assets",
    "systemBundle": bundlePath,
    "runtimeVersion": ProcessInfo.processInfo.operatingSystemVersionString,
    "resources": [[String: Any]](),
]
var missing: [String] = []
var missingOptional: [String] = []
do {
    let context = try Data(contentsOf: output.appendingPathComponent("context.json"))
    result["context"] = try JSONSerialization.jsonObject(with: context)
    let bundle = Bundle(path: bundlePath)
    result["bundleVersion"] = bundle?.object(forInfoDictionaryKey: "CFBundleVersion") ?? NSNull()
    var resources: [[String: Any]] = []
    for name in resourceNames {
        let required = requiredResourceNames.contains(name)
        guard let image = bundle?.image(forResource: NSImage.Name(name)) else {
            if required { missing.append(name) } else { missingOptional.append(name) }
            resources.append(["name": name, "required": required, "available": false])
            continue
        }
        let png = try renderedPNG(image, scale: 4)
        let file = "\(name)@4x.png"
        try png.write(to: output.appendingPathComponent(file), options: .atomic)
        var entry: [String: Any] = [
            "name": name, "required": required, "available": true,
            "sizePoints": ["width": image.size.width, "height": image.size.height],
            "isTemplate": image.isTemplate,
            "png": file, "renderScale": 4, "pngSHA256": digest(png),
            "representations": image.representations.map { representation in
                [
                    "class": String(describing: type(of: representation)),
                    "pixelsWide": representation.pixelsWide,
                    "pixelsHigh": representation.pixelsHigh,
                    "sizePoints": [
                        "width": representation.size.width,
                        "height": representation.size.height,
                    ],
                ] as [String: Any]
            },
        ]
        if let tiff = image.tiffRepresentation {
            entry["decodedTIFFSHA256"] = digest(tiff)
        }
        resources.append(entry)
    }
    result["resources"] = resources
    result["requiredResourceNames"] = requiredResourceNames
    result["optionalResourceNames"] = optionalResourceNames
    result["missingResources"] = missing
    result["missingOptionalResources"] = missingOptional
    result["allKnownResourcesAvailable"] = missing.isEmpty
    result["status"] = missing.isEmpty ? "complete" : "missing-resources"
} catch {
    result["status"] = "failed"
    result["error"] = String(describing: error)
}
do {
    let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: output.appendingPathComponent("artwork.json"), options: .atomic)
} catch {
    fputs("Cannot preserve artwork evidence: \(error)\n", stderr)
    exit(1)
}
guard result["status"] as? String == "complete" else {
    fputs("System battery artwork probe did not complete; inspect artwork.json.\n", stderr)
    exit(1)
}
print("SYSTEM_BATTERY_ARTWORK_PROBE_PASSED resources=\(requiredResourceNames.count) optionalAvailable=\(optionalResourceNames.count - missingOptional.count)")

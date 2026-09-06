#!/usr/bin/env swift

import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct IconSpec: Decodable { let icons: [String] }
enum PackagingError: Error { case invalidRaster(String) }

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let design = root.appendingPathComponent("Design/IconSystem")
let assets = root.appendingPathComponent("Sources/CodexTokenLedger/Resources/Assets.xcassets")
let spec = try JSONDecoder().decode(IconSpec.self, from: Data(contentsOf: design.appendingPathComponent("icon-system.json")))
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

func glyph(at url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw PackagingError.invalidRaster(url.path) }
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let normalized: CGImage = try pixels.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace, bitmapInfo: bitmapInfo)
        else { throw PackagingError.invalidRaster(url.path) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The generated masters have a light matte, not an alpha channel.
        // Recover coverage from their existing ink; no glyph geometry is drawn.
        for i in stride(from: 0, to: buffer.count, by: 4) {
            let gray = (Double(buffer[i]) + Double(buffer[i + 1]) + Double(buffer[i + 2])) / 3
            let alpha = UInt8((max(0, min(1, (235 - gray) / 195)) * 255).rounded())
            buffer[i] = 0; buffer[i + 1] = 0; buffer[i + 2] = 0; buffer[i + 3] = alpha
        }
        guard let result = context.makeImage() else { throw PackagingError.invalidRaster(url.path) }
        return result
    }
    var minX = width, minY = height, maxX = -1, maxY = -1
    for y in 0..<height {
        for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 3 {
            minX = min(minX, x); minY = min(minY, y)
            maxX = max(maxX, x); maxY = max(maxY, y)
        }
    }
    guard maxX >= minX, minX > 2, minY > 2, maxX < width - 3, maxY < height - 3,
          let cropped = normalized.cropping(to: CGRect(x: minX - 1, y: minY - 1,
                                                       width: maxX - minX + 3, height: maxY - minY + 3))
    else { throw PackagingError.invalidRaster("Empty or edge-clipped glyph: \(url.path)") }
    return cropped
}

func png(_ glyph: CGImage, size: Int, white: Bool = false) throws -> Data {
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: size * 4, space: colorSpace, bitmapInfo: bitmapInfo)
    else { throw PackagingError.invalidRaster("Output context") }
    context.interpolationQuality = .high
    let available = CGFloat(size) * 0.79
    let scale = min(available / CGFloat(glyph.width), available / CGFloat(glyph.height))
    let w = CGFloat(glyph.width) * scale, h = CGFloat(glyph.height) * scale
    context.draw(glyph, in: CGRect(x: (CGFloat(size) - w) / 2, y: (CGFloat(size) - h) / 2, width: w, height: h))
    if white {
        context.setBlendMode(.sourceIn)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }
    let data = NSMutableData()
    guard let output = context.makeImage(),
          let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { throw PackagingError.invalidRaster("PNG destination") }
    CGImageDestinationAddImage(destination, output, nil)
    guard CGImageDestinationFinalize(destination) else { throw PackagingError.invalidRaster("PNG encode") }
    return data as Data
}

for name in spec.icons {
    let image = try glyph(at: design.appendingPathComponent("Generated/\(name).png"))
    let imageSet = assets.appendingPathComponent("PulseIcon-\(name).imageset")
    try FileManager.default.createDirectory(at: imageSet, withIntermediateDirectories: true)
    var entries: [[String: String]] = []
    for scale in 1...3 {
        let filename = name + (scale == 1 ? "" : "@\(scale)x") + ".png"
        let data = try png(image, size: 24 * scale)
        try data.write(to: imageSet.appendingPathComponent(filename), options: .atomic)
        try data.write(to: design.appendingPathComponent("png/\(filename)"), options: .atomic)
        entries.append(["filename": filename, "idiom": "universal", "scale": "\(scale)x"])
    }
    let contents: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1],
                                   "properties": ["template-rendering-intent": "template"]]
    try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
        .write(to: imageSet.appendingPathComponent("Contents.json"), options: .atomic)
    for mode in ["light", "dark"] {
        let directory = design.appendingPathComponent("preview/\(mode)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png(image, size: 128, white: mode == "dark").write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
    }
}

// Contact sheets show the packaged raster at inspection and actual UI sizes.
for mode in ["light", "dark"] {
    let columns = 6, cellWidth = 140, cellHeight = 140
    let rows = (spec.icons.count + columns - 1) / columns
    let size = NSSize(width: columns * cellWidth, height: rows * cellHeight)
    let image = NSImage(size: size)
    image.lockFocus()
    (mode == "dark" ? NSColor(calibratedWhite: 0.10, alpha: 1) : NSColor(calibratedWhite: 0.96, alpha: 1)).setFill()
    NSRect(origin: .zero, size: size).fill()
    for (i, name) in spec.icons.enumerated() {
        let x = i % columns * cellWidth, y = rows * cellHeight - (i / columns + 1) * cellHeight
        guard let icon = NSImage(contentsOf: design.appendingPathComponent("preview/\(mode)/\(name).png"))
        else { throw PackagingError.invalidRaster(name) }
        icon.draw(in: NSRect(x: x + 38, y: y + 56, width: 64, height: 64))
        icon.draw(in: NSRect(x: x + 45, y: y + 27, width: 16, height: 16))
        icon.draw(in: NSRect(x: x + 74, y: y + 23, width: 24, height: 24))
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11),
                                                         .foregroundColor: mode == "dark" ? NSColor.white : NSColor.darkGray]
        let label = name as NSString
        let width = label.size(withAttributes: attributes).width
        label.draw(at: NSPoint(x: CGFloat(x) + (CGFloat(cellWidth) - width) / 2, y: CGFloat(y + 7)), withAttributes: attributes)
    }
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:])
    else { throw PackagingError.invalidRaster("Contact sheet") }
    try data.write(to: design.appendingPathComponent("sheets/contact-sheet-\(mode).png"), options: .atomic)
}
print("Packaged \(spec.icons.count) image-generated icons, 1x/2x/3x and transparent previews")

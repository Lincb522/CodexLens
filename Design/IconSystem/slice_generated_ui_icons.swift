#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// The source sheet is generated with the built-in image model. This script only
// packages its 4 x 6 raster cells into the PNG sizes consumed by Xcode.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let sheetURL = root.appendingPathComponent("Design/IconSystem/generated-ui-icon-sheet-v2.png")
let assetRoot = root.appendingPathComponent("Sources/CodexTokenLedger/Resources/Assets.xcassets")
let designPNGRoot = root.appendingPathComponent("Design/IconSystem/png", isDirectory: true)

let names = [
    "overview", "pulse", "ledger", "console",
    "account", "tasks", "quota", "credits",
    "appearance", "language", "data", "developer",
    "sync", "search", "calendar", "timer",
    "folder", "export", "check", "warning",
    "arrow-left", "arrow-right", "chevron-down", "more",
]

guard let source = CGImageSourceCreateWithURL(sheetURL as CFURL, nil),
      let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fatalError("Missing generated raster sheet at \(sheetURL.path)")
}

try FileManager.default.createDirectory(at: designPNGRoot, withIntermediateDirectories: true)

func rgbaImage(from image: CGImage) -> (CGImage, [UInt8], Int, Int) {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (context.makeImage()!, pixels, width, height)
}

func opaqueBounds(pixels: [UInt8], width: Int, height: Int) -> CGRect {
    var minX = width
    var minY = height
    var maxX = -1
    var maxY = -1
    for y in 0..<height {
        for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 18 {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }
    guard maxX >= minX, maxY >= minY else { return .zero }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

func renderedPNG(glyph: CGImage, size: Int) -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    let inset = CGFloat(size) * 0.105
    let available = CGFloat(size) - inset * 2
    let scale = min(available / CGFloat(glyph.width), available / CGFloat(glyph.height))
    let drawWidth = CGFloat(glyph.width) * scale
    let drawHeight = CGFloat(glyph.height) * scale
    let rect = CGRect(
        x: (CGFloat(size) - drawWidth) / 2,
        y: (CGFloat(size) - drawHeight) / 2,
        width: drawWidth,
        height: drawHeight
    )
    context.draw(glyph, in: rect)
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(
        output as CFMutableData,
        UTType.png.identifier as CFString,
        1,
        nil
    )!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return output as Data
}

let cellWidth = CGFloat(sheet.width) / 4
let cellHeight = CGFloat(sheet.height) / 6
for (index, name) in names.enumerated() {
    let column = index % 4
    let rowFromTop = index / 4
    let cell = CGRect(
        x: (CGFloat(column) * cellWidth).rounded(.down),
        y: (CGFloat(rowFromTop) * cellHeight).rounded(.down),
        width: cellWidth.rounded(.up),
        height: cellHeight.rounded(.up)
    ).intersection(CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height))
    guard let croppedCell = sheet.cropping(to: cell) else { fatalError("Could not crop \(name)") }
    let (normalized, pixels, width, height) = rgbaImage(from: croppedCell)
    let bounds = opaqueBounds(pixels: pixels, width: width, height: height)
    guard bounds != .zero, let glyph = normalized.cropping(to: bounds) else {
        fatalError("Generated sheet cell is empty: \(name)")
    }

    let imageSet = assetRoot.appendingPathComponent("PulseIcon-\(name).imageset", isDirectory: true)
    try FileManager.default.createDirectory(at: imageSet, withIntermediateDirectories: true)
    for scale in 1...3 {
        let filename = name + (scale == 1 ? "" : "@\(scale)x") + ".png"
        let data = renderedPNG(glyph: glyph, size: 24 * scale)
        try data.write(to: imageSet.appendingPathComponent(filename), options: .atomic)
        try data.write(to: designPNGRoot.appendingPathComponent(filename), options: .atomic)
    }
}

print("Packaged \(names.count) image-generated UI icons from \(sheetURL.lastPathComponent)")

// make_icon.swift — build the 1024x1024 macOS icon canvas from icon.png
//
// macOS icon grid: the *visible* artwork occupies 824x824 inside a 1024x1024
// canvas (80.5%), which is what keeps the icon from looking oversized in the
// Dock. The source art already carries its own transparent padding, so the
// alpha bounding box is cropped first and *that* is scaled to 824; scaling the
// raw canvas instead would shrink the visible art to ~59%.
//
// Produces:
//   icon_adjusted.png         transparent canvas (824 art, centered)
//   icon_adjusted_opaque.png  same art on a seamless opaque squircle plate,
//                             as a fallback for macOS 26's grey backdrop
//
// Usage: swift Scripts/make_icon.swift [input.png]

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let canvasSize = 1024
let alphaThreshold: UInt8 = 8
let opaqueAlphaThreshold: UInt8 = 240

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("error: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
let inputPath = args.count > 1 ? args[1] : "icon.png"
let inputURL = URL(fileURLWithPath: inputPath)
guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fail("cannot read \(inputPath)")
}

// Normalise to premultiplied RGBA8 so the pixel scan below is unambiguous.
let width = cgImage.width
let height = cgImage.height
let bytesPerRow = width * 4
var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let srcContext = CGContext(data: &pixels,
                                 width: width, height: height,
                                 bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                 space: colorSpace,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fail("cannot create source bitmap context")
}
srcContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

// MARK: - alpha bounding box

var minX = width, minY = height, maxX = -1, maxY = -1
for y in 0..<height {
    let row = y * bytesPerRow
    for x in 0..<width {
        if pixels[row + x * 4 + 3] > alphaThreshold {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
}
guard maxX >= minX, maxY >= minY else { fail("image is fully transparent") }
let bbox = CGRect(x: minX, y: minY,
                  width: maxX - minX + 1, height: maxY - minY + 1)
print("source \(width)x\(height), alpha bbox \(Int(bbox.width))x\(Int(bbox.height)) at (\(minX),\(minY))")

// MARK: - edge colours (used by the opaque fallback plate)
//
// The artwork's own frame is not a flat colour: it runs from dark indigo at the
// top-left to a lighter blue at the bottom-right. Sampling a single average
// therefore leaves a visible "sticker" halo, so the ring is sampled in two
// diagonal clusters and the plate is filled with a matching gradient.
var tl = (r: 0.0, g: 0.0, b: 0.0)
var br = (r: 0.0, g: 0.0, b: 0.0)
var tlCount = 0
var brCount = 0
let borderInset = 18
let midX = bbox.midX
let midY = bbox.midY
for y in Int(bbox.minY)..<Int(bbox.maxY) {
    let row = y * bytesPerRow
    for x in Int(bbox.minX)..<Int(bbox.maxX) {
        // Only the band just inside the frame, where the artwork is already
        // opaque; the outermost few pixels are anti-aliased rim.
        let insetBand = x < Int(bbox.minX) + borderInset || x > Int(bbox.maxX) - borderInset
            || y < Int(bbox.minY) + borderInset || y > Int(bbox.maxY) - borderInset
        let tooCloseToRim = x < Int(bbox.minX) + 4 || x > Int(bbox.maxX) - 4
            || y < Int(bbox.minY) + 4 || y > Int(bbox.maxY) - 4
        guard insetBand, !tooCloseToRim else { continue }
        let i = row + x * 4
        let a = Double(pixels[i + 3]) / 255.0
        guard a > 0.94 else { continue }        // skip anti-aliased rim pixels
        let r = Double(pixels[i]) / a           // un-premultiply
        let g = Double(pixels[i + 1]) / a
        let b = Double(pixels[i + 2]) / a
        if CGFloat(x) + CGFloat(y) < midX + midY {
            tl.r += r; tl.g += g; tl.b += b; tlCount += 1
        } else {
            br.r += r; br.g += g; br.b += b; brCount += 1
        }
    }
}
guard tlCount > 0, brCount > 0 else { fail("no opaque edge pixels found") }
func avg(_ c: (r: Double, g: Double, b: Double), _ n: Int) -> CGColor {
    CGColor(colorSpace: colorSpace,
            components: [CGFloat(c.r / Double(n) / 255.0),
                         CGFloat(c.g / Double(n) / 255.0),
                         CGFloat(c.b / Double(n) / 255.0),
                         1.0])!
}
let plateStart = avg(tl, tlCount)
let plateEnd = avg(br, brCount)
print(String(format: "plate gradient  TL=(%.3f,%.3f,%.3f) @%d  BR=(%.3f,%.3f,%.3f) @%d",
             tl.r / Double(tlCount) / 255, tl.g / Double(tlCount) / 255, tl.b / Double(tlCount) / 255, tlCount,
             br.r / Double(brCount) / 255, br.g / Double(brCount) / 255, br.b / Double(brCount) / 255, brCount))

// The pixel scan above walks the bitmap rows top-down, and CGImage.cropping
// also uses a top-left origin for images decoded from a file, so the bounding
// box can be used as-is. (Flipping y here would shift the crop up by ~27px and
// clip the bottom of the artwork.)
let cropRect = bbox
guard let cropped = cgImage.cropping(to: cropRect) else { fail("crop failed") }

// MARK: - drawing helpers

func makeContext() -> CGContext {
    guard let ctx = CGContext(data: nil, width: canvasSize, height: canvasSize,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fail("cannot create canvas context")
    }
    ctx.interpolationQuality = .high
    ctx.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
    return ctx
}

// The artwork fills the whole 1024 canvas: aspect-fill (nothing stretched),
// centered, overflow clipped at the canvas edge.
//
// macOS 26 only draws an icon as a native rounded square when its artwork is
// opaque right up to the canvas border. Any transparent margin or corner makes
// IconServices treat it as a legacy icon and paint a grey plate behind it --
// verified by rendering each variant through NSWorkspace. So this is full-bleed
// on purpose: 824-style padding is exactly what triggers the grey plate.
let fillScale = max(CGFloat(canvasSize) / bbox.width, CGFloat(canvasSize) / bbox.height)
let fillW = bbox.width * fillScale
let fillH = bbox.height * fillScale
let artRect = CGRect(x: (CGFloat(canvasSize) - fillW) / 2,
                     y: (CGFloat(canvasSize) - fillH) / 2,
                     width: fillW, height: fillH)

func writePNG(_ ctx: CGContext, to path: String) {
    guard let out = ctx.makeImage() else { fail("cannot snapshot context") }
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("cannot create \(path)")
    }
    CGImageDestinationAddImage(dest, out, nil)
    guard CGImageDestinationFinalize(dest) else { fail("cannot write \(path)") }
    print("wrote \(path)  \(canvasSize)x\(canvasSize)")
}

// The artwork's own rounded corners stay transparent, so a gradient drawn from
// its frame colours sits underneath and fills those notches seamlessly.
let ctx = makeContext()
ctx.saveGState()
ctx.addRect(CGRect(x: 0, y: 0, width: CGFloat(canvasSize), height: CGFloat(canvasSize)))
ctx.clip()
let gradient = CGGradient(colorsSpace: colorSpace,
                          colors: [plateStart, plateEnd] as CFArray,
                          locations: [0, 1])!
// CG's y axis points up, so the artwork's top-left corner is (0, canvasSize).
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: CGFloat(canvasSize)),
                       end: CGPoint(x: CGFloat(canvasSize), y: 0),
                       options: [])
ctx.restoreGState()
ctx.draw(cropped, in: artRect)
writePNG(ctx, to: "icon_adjusted.png")

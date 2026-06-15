import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// PantryChef app icon — the shipped "plate & dot" mark, drawn flat and crisp at
// 1024² so it can be regenerated from source instead of living only as a binary.
// A cream plate ring on the ink-green ground, a tomato dot riding the rim.
//
//   swift tools/make_app_icon.swift PantryChef/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//
// (Field Notes palette: ink #223D2A, cream #F3EAD3, tomato #C24B33.)

let S: CGFloat = 1024
func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    CGColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
}
let cream = rgb(243, 234, 211)
let ink   = rgb(34, 61, 42)
let tomato = rgb(194, 75, 51)

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "PantryChef/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                          bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("could not create context")
}

let center = CGPoint(x: S/2, y: S/2)
// Ground.
ctx.setFillColor(ink)
ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
// Plate ring.
let r: CGFloat = 307, lineWidth: CGFloat = 42
ctx.setStrokeColor(cream); ctx.setLineWidth(lineWidth)
ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2*r, height: 2*r))
// Tomato dot riding the upper-right rim (CG origin is bottom-left).
let dot = CGPoint(x: 698, y: S - 344), dotR: CGFloat = 70
ctx.setFillColor(tomato)
ctx.fillEllipse(in: CGRect(x: dot.x - dotR, y: dot.y - dotR, width: 2*dotR, height: 2*dotR))

guard let img = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) else {
    fatalError("could not write \(outPath)")
}
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote app icon -> \(outPath)")

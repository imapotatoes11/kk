import AppKit
import Foundation

let output = CommandLine.arguments[1]
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
let background = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 205, yRadius: 205)
NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.23, blue: 0.30, alpha: 1), ending: NSColor(calibratedRed: 0.07, green: 0.11, blue: 0.16, alpha: 1))!.draw(in: background, angle: -90)
let screen = NSBezierPath(roundedRect: NSRect(x: 230, y: 330, width: 564, height: 397), xRadius: 64, yRadius: 64)
screen.lineWidth = 30
NSColor(calibratedWhite: 0.94, alpha: 1).setStroke()
screen.stroke()
let base = NSBezierPath()
base.lineWidth = 30
base.lineCapStyle = .round
base.move(to: NSPoint(x: 415, y: 254))
base.line(to: NSPoint(x: 610, y: 254))
base.stroke()
let stem = NSBezierPath()
stem.lineWidth = 30
stem.move(to: NSPoint(x: 512, y: 330))
stem.line(to: NSPoint(x: 512, y: 254))
stem.stroke()
let bubble = NSBezierPath(roundedRect: NSRect(x: 354, y: 440, width: 316, height: 170), xRadius: 55, yRadius: 55)
NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.76, alpha: 1).setFill()
bubble.fill()
let tail = NSBezierPath()
tail.move(to: NSPoint(x: 420, y: 451))
tail.line(to: NSPoint(x: 408, y: 409))
tail.line(to: NSPoint(x: 477, y: 449))
tail.close()
tail.fill()
NSColor(calibratedRed: 0.08, green: 0.17, blue: 0.19, alpha: 1).setFill()
for x in [440, 512, 584] { NSBezierPath(ovalIn: NSRect(x: x - 15, y: 510, width: 30, height: 30)).fill() }
image.unlockFocus()
let tiff = image.tiffRepresentation!
let bitmap = NSBitmapImageRep(data: tiff)!
let png = bitmap.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: output))

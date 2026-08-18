#!/usr/bin/env bash
# Generates Resources/AppIcon.icns from a single generated PNG — a flat
# rounded-square with a gauge glyph, drawn via Core Graphics through a
# tiny Swift script so there's no external image dependency.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/draw.swift" <<'EOF'
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let background = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size), xRadius: size * 0.22, yRadius: size * 0.22)
NSColor(calibratedRed: 0.13, green: 0.55, blue: 0.98, alpha: 1.0).setFill()
background.fill()

let gauge = NSBezierPath()
gauge.appendArc(withCenter: NSPoint(x: size / 2, y: size / 2), radius: size * 0.30, startAngle: 20, endAngle: 160)
gauge.lineWidth = size * 0.06
NSColor.white.setStroke()
gauge.stroke()

let needle = NSBezierPath()
needle.move(to: NSPoint(x: size / 2, y: size / 2))
needle.line(to: NSPoint(x: size * 0.68, y: size * 0.62))
needle.lineWidth = size * 0.045
NSColor.white.setStroke()
needle.stroke()

let hub = NSBezierPath(ovalIn: NSRect(x: size / 2 - size * 0.035, y: size / 2 - size * 0.035, width: size * 0.07, height: size * 0.07))
NSColor.white.setFill()
hub.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to render icon")
}
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
EOF

swift "$WORK/draw.swift" "$WORK/icon-1024.png"

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 64 128 256 512; do
    sips -z "$size" "$size" "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"

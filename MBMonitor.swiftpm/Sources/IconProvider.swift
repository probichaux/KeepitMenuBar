import AppKit

/// Loads connector icons and provides the menubar template image.
enum IconProvider {
    /// Returns an NSImage for the given connector type.
    /// Falls back to an SF Symbol.
    static func icon(for type: ConnectorType, size: CGFloat = 20) -> NSImage? {
        NSImage(systemSymbolName: type.icon, accessibilityDescription: type.displayName)
    }

    /// Returns the Keepit logo as a menubar template image, drawn as a bezier path.
    /// The path data comes from the official keepit_logo.svg.
    static func menuBarIcon() -> NSImage? {
        // SVG viewBox: 0 0 46.84 23.22
        let svgWidth: CGFloat = 46.84
        let svgHeight: CGFloat = 23.22

        // Target: 18pt tall for menubar, width scales proportionally
        let targetHeight: CGFloat = 18
        let scale = targetHeight / svgHeight
        let targetWidth = svgWidth * scale

        let image = NSImage(size: NSSize(width: targetWidth, height: targetHeight), flipped: false) { rect in
            let transform = NSAffineTransform()
            transform.scaleX(by: scale, yBy: scale)
            transform.concat()

            let path = NSBezierPath()
            // Keepit double-loop logo path from keepit_logo.svg
            path.move(to: NSPoint(x: 11.7, y: 23.22 - 23.21))
            // Use the raw SVG commands converted to absolute coordinates, flipped Y
            keepitLogoPath(path, h: svgHeight)

            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Traces the Keepit logo path. SVG Y is flipped (0=top), NSBezierPath Y is 0=bottom.
    private static func keepitLogoPath(_ p: NSBezierPath, h: CGFloat) {
        // Helper to flip Y: SVG has y=0 at top, Quartz at bottom
        func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: h - y) }

        p.move(to: pt(11.7, 23.21))

        // Left loop (outer)
        p.curve(to: pt(3.38, 19.8), controlPoint1: pt(8.56, 23.21), controlPoint2: pt(5.59, 21.97))
        p.curve(to: pt(0, 11.62), controlPoint1: pt(1.18, 17.62), controlPoint2: pt(0, 14.74))
        p.curve(to: pt(11.7, 0), controlPoint1: pt(0, 5.32), controlPoint2: pt(5.36, 0))
        p.curve(to: pt(20.72, 3.95), controlPoint1: pt(15.76, 0), controlPoint2: pt(18.85, 2.15))
        p.curve(to: pt(21.71, 5.58), controlPoint1: pt(20.89, 4.11), controlPoint2: pt(21.72, 4.95))
        p.curve(to: pt(21.37, 6.61), controlPoint1: pt(21.71, 6.07), controlPoint2: pt(21.47, 6.45))
        p.line(to: pt(17.73, 12.55))
        p.curve(to: pt(16.68, 13.14), controlPoint1: pt(17.55, 12.82), controlPoint2: pt(17.16, 13.14))
        p.line(to: pt(7.27, 13.14))
        p.curve(to: pt(6.92, 12.96), controlPoint1: pt(7.11, 13.14), controlPoint2: pt(6.98, 13.08))
        p.curve(to: pt(6.94, 12.58), controlPoint1: pt(6.85, 12.84), controlPoint2: pt(6.86, 12.7))
        p.curve(to: pt(8.57, 10.13), controlPoint1: pt(7.14, 12.26), controlPoint2: pt(8.38, 10.39))
        p.curve(to: pt(9.25, 9.84), controlPoint1: pt(8.79, 9.84), controlPoint2: pt(9.0, 9.84))
        p.line(to: pt(15.53, 9.84))
        p.curve(to: pt(16.19, 9.52), controlPoint1: pt(15.9, 9.84), controlPoint2: pt(16.02, 9.8))
        p.curve(to: pt(17.42, 7.45), controlPoint1: pt(16.19, 9.52), controlPoint2: pt(17.17, 7.86))
        p.curve(to: pt(17.36, 6.93), controlPoint1: pt(17.51, 7.31), controlPoint2: pt(17.53, 7.1))
        p.curve(to: pt(11.71, 4.43), controlPoint1: pt(15.01, 4.75), controlPoint2: pt(12.81, 4.43))
        p.curve(to: pt(4.4, 11.68), controlPoint1: pt(7.54, 4.43), controlPoint2: pt(4.4, 7.55))
        p.curve(to: pt(6.33, 16.86), controlPoint1: pt(4.4, 13.68), controlPoint2: pt(5.09, 15.52))
        p.curve(to: pt(11.71, 19.07), controlPoint1: pt(7.67, 18.3), controlPoint2: pt(9.53, 19.07))
        p.curve(to: pt(17.41, 16.82), controlPoint1: pt(13.71, 19.07), controlPoint2: pt(15.4, 18.94))
        p.curve(to: pt(19.74, 13.59), controlPoint1: pt(18.46, 15.72), controlPoint2: pt(19.73, 13.61))

        // Bridge between loops
        p.curve(to: pt(23.87, 6.65), controlPoint1: pt(19.74, 13.59), controlPoint2: pt(22.85, 8.37))
        p.curve(to: pt(26.26, 3.67), controlPoint1: pt(24.33, 5.87), controlPoint2: pt(25.25, 4.61))
        p.curve(to: pt(35.1, 0), controlPoint1: pt(28.04, 2.0), controlPoint2: pt(31.03, 0))

        // Right loop (outer)
        p.curve(to: pt(46.84, 11.73), controlPoint1: pt(41.57, 0), controlPoint2: pt(46.84, 5.26))
        p.curve(to: pt(35.23, 23.21), controlPoint1: pt(46.84, 18.2), controlPoint2: pt(41.74, 23.21))
        p.curve(to: pt(26.33, 19.23), controlPoint1: pt(31.46, 23.21), controlPoint2: pt(27.89, 21.23))
        p.curve(to: pt(25.37, 17.45), controlPoint1: pt(25.96, 18.75), controlPoint2: pt(25.39, 18.03))
        p.curve(to: pt(25.61, 16.5), controlPoint1: pt(25.36, 17.07), controlPoint2: pt(25.49, 16.7))
        p.curve(to: pt(28.98, 10.9), controlPoint1: pt(26.15, 15.58), controlPoint2: pt(27.28, 13.71))
        p.curve(to: pt(30.01, 10.32), controlPoint1: pt(29.22, 10.55), controlPoint2: pt(29.62, 10.32))
        p.line(to: pt(39.45, 10.32))
        p.curve(to: pt(39.8, 10.5), controlPoint1: pt(39.61, 10.32), controlPoint2: pt(39.73, 10.39))
        p.curve(to: pt(39.78, 10.88), controlPoint1: pt(39.86, 10.62), controlPoint2: pt(39.86, 10.76))
        p.curve(to: pt(38.16, 13.34), controlPoint1: pt(39.59, 11.19), controlPoint2: pt(38.36, 13.07))
        p.curve(to: pt(37.48, 13.63), controlPoint1: pt(37.94, 13.63), controlPoint2: pt(37.73, 13.63))
        p.line(to: pt(31.26, 13.63))
        p.curve(to: pt(30.6, 13.94), controlPoint1: pt(30.89, 13.63), controlPoint2: pt(30.77, 13.67))
        p.curve(to: pt(29.33, 16.03), controlPoint1: pt(30.28, 14.46), controlPoint2: pt(29.33, 16.03))
        p.curve(to: pt(29.35, 16.54), controlPoint1: pt(29.23, 16.19), controlPoint2: pt(29.24, 16.37))
        p.curve(to: pt(29.91, 17.14), controlPoint1: pt(29.52, 16.77), controlPoint2: pt(29.91, 17.14))
        p.curve(to: pt(35.1, 19.07), controlPoint1: pt(31.12, 18.36), controlPoint2: pt(33.13, 19.07))
        p.curve(to: pt(42.42, 11.68), controlPoint1: pt(39.38, 19.07), controlPoint2: pt(42.42, 15.94))
        p.curve(to: pt(35.1, 4.43), controlPoint1: pt(42.42, 7.68), controlPoint2: pt(38.82, 4.43))
        p.curve(to: pt(29.29, 6.88), controlPoint1: pt(32.9, 4.43), controlPoint2: pt(30.94, 5.25))
        p.curve(to: pt(27.04, 9.96), controlPoint1: pt(28.34, 7.81), controlPoint2: pt(27.62, 9.0))

        // Bridge back
        p.curve(to: pt(23.16, 16.55), controlPoint1: pt(27.04, 9.96), controlPoint2: pt(23.77, 15.6))
        p.curve(to: pt(11.7, 23.21), controlPoint1: pt(21.22, 19.58), controlPoint2: pt(17.66, 23.21))

        p.close()
    }
}

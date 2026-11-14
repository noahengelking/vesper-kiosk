import AppKit
import CoreImage
import SwiftUI

enum ImageColors {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func analyze(_ image: NSImage) -> [Color] {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cgImage = bitmap.cgImage else {
            return [Color(hex: 0x2A2118), Color(hex: 0x17120D)]
        }

        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        let regions: [CGRect] = [
            extent,
            CGRect(x: extent.minX, y: extent.midY, width: extent.width * 0.55, height: extent.height * 0.55),
            CGRect(x: extent.midX, y: extent.minY, width: extent.width * 0.55, height: extent.height * 0.55)
        ]

        var colors: [Color] = []
        for region in regions {
            guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: ciImage,
                kCIInputExtentKey: CIVector(cgRect: region)
            ]), let output = filter.outputImage else { continue }

            var pixel = [UInt8](repeating: 0, count: 4)
            context.render(
                output,
                toBitmap: &pixel,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            let color = Color(
                .sRGB,
                red: Double(pixel[0]) / 255,
                green: Double(pixel[1]) / 255,
                blue: Double(pixel[2]) / 255,
                opacity: 1
            )
            colors.append(color)
        }
        return colors.isEmpty ? [Color(hex: 0x2A2118), Color(hex: 0x17120D)] : colors
    }
}

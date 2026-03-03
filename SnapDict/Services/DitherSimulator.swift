import CoreGraphics
import Foundation

enum DitherSimulator {
    static func apply(
        to image: CGImage,
        type: Constants.DitherType,
        kernel: Constants.DitherKernel
    ) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        // 转灰度 Float 数组
        var pixels = grayscalePixels(from: image, width: width, height: height)
        guard !pixels.isEmpty else { return nil }

        switch type {
        case .none:
            thresholdBinarize(&pixels)
        case .ordered:
            orderedDither(&pixels, width: width, height: height)
        case .diffusion:
            errorDiffusion(&pixels, width: width, height: height, kernel: kernel)
        }

        return makeBinaryImage(from: pixels, width: width, height: height)
    }

    // MARK: - Grayscale Conversion

    private static func grayscalePixels(from image: CGImage, width: Int, height: Int) -> [Float] {
        let count = width * height
        var rgba = [UInt8](repeating: 0, count: count * 4)

        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var gray = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let r = Float(rgba[i * 4])
            let g = Float(rgba[i * 4 + 1])
            let b = Float(rgba[i * 4 + 2])
            gray[i] = 0.299 * r + 0.587 * g + 0.114 * b
        }
        return gray
    }

    // MARK: - Threshold Binarize

    private static func thresholdBinarize(_ pixels: inout [Float]) {
        for i in pixels.indices {
            pixels[i] = pixels[i] > 127.5 ? 255 : 0
        }
    }

    // MARK: - Ordered Dither (4x4 Bayer)

    private static let bayerMatrix: [[Float]] = [
        [ 0, 8, 2, 10],
        [12, 4, 14,  6],
        [ 3, 11, 1,  9],
        [15, 7, 13,  5]
    ]

    private static func orderedDither(_ pixels: inout [Float], width: Int, height: Int) {
        for y in 0..<height {
            for x in 0..<width {
                let threshold = (bayerMatrix[y % 4][x % 4] + 0.5) / 16.0 * 255.0
                let idx = y * width + x
                pixels[idx] = pixels[idx] > threshold ? 255 : 0
            }
        }
    }

    // MARK: - Error Diffusion

    private struct DiffusionEntry {
        let dx: Int
        let dy: Int
        let weight: Float
    }

    private static func errorDiffusion(
        _ pixels: inout [Float],
        width: Int,
        height: Int,
        kernel: Constants.DitherKernel
    ) {
        let entries = diffusionKernel(for: kernel)

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let old = pixels[idx]
                let new: Float = old > 127.5 ? 255 : 0
                pixels[idx] = new
                let error = old - new

                for entry in entries {
                    let nx = x + entry.dx
                    let ny = y + entry.dy
                    if nx >= 0, nx < width, ny < height {
                        pixels[ny * width + nx] += error * entry.weight
                    }
                }
            }
        }
    }

    // swiftlint:disable function_body_length
    private static func diffusionKernel(for kernel: Constants.DitherKernel) -> [DiffusionEntry] {
        switch kernel {
        case .floydSteinberg:
            return [
                DiffusionEntry(dx: 1, dy: 0, weight: 7.0 / 16),
                DiffusionEntry(dx: -1, dy: 1, weight: 3.0 / 16),
                DiffusionEntry(dx: 0, dy: 1, weight: 5.0 / 16),
                DiffusionEntry(dx: 1, dy: 1, weight: 1.0 / 16),
            ]

        case .jarvisJudiceNinke:
            let d: Float = 48
            return [
                DiffusionEntry(dx: 1, dy: 0, weight: 7 / d), DiffusionEntry(dx: 2, dy: 0, weight: 5 / d),
                DiffusionEntry(dx: -2, dy: 1, weight: 3 / d), DiffusionEntry(dx: -1, dy: 1, weight: 5 / d),
                DiffusionEntry(dx: 0, dy: 1, weight: 7 / d), DiffusionEntry(dx: 1, dy: 1, weight: 5 / d),
                DiffusionEntry(dx: 2, dy: 1, weight: 3 / d),
                DiffusionEntry(dx: -2, dy: 2, weight: 1 / d), DiffusionEntry(dx: -1, dy: 2, weight: 3 / d),
                DiffusionEntry(dx: 0, dy: 2, weight: 5 / d), DiffusionEntry(dx: 1, dy: 2, weight: 3 / d),
                DiffusionEntry(dx: 2, dy: 2, weight: 1 / d),
            ]

        case .stucki:
            let d: Float = 42
            return [
                DiffusionEntry(dx: 1, dy: 0, weight: 8 / d), DiffusionEntry(dx: 2, dy: 0, weight: 4 / d),
                DiffusionEntry(dx: -2, dy: 1, weight: 2 / d), DiffusionEntry(dx: -1, dy: 1, weight: 4 / d),
                DiffusionEntry(dx: 0, dy: 1, weight: 8 / d), DiffusionEntry(dx: 1, dy: 1, weight: 4 / d),
                DiffusionEntry(dx: 2, dy: 1, weight: 2 / d),
                DiffusionEntry(dx: -2, dy: 2, weight: 1 / d), DiffusionEntry(dx: -1, dy: 2, weight: 2 / d),
                DiffusionEntry(dx: 0, dy: 2, weight: 4 / d), DiffusionEntry(dx: 1, dy: 2, weight: 2 / d),
                DiffusionEntry(dx: 2, dy: 2, weight: 1 / d),
            ]

        case .atkinson:
            let d: Float = 8
            return [
                DiffusionEntry(dx: 1, dy: 0, weight: 1 / d), DiffusionEntry(dx: 2, dy: 0, weight: 1 / d),
                DiffusionEntry(dx: -1, dy: 1, weight: 1 / d), DiffusionEntry(dx: 0, dy: 1, weight: 1 / d),
                DiffusionEntry(dx: 1, dy: 1, weight: 1 / d),
                DiffusionEntry(dx: 0, dy: 2, weight: 1 / d),
            ]

        case .burkes:
            let d: Float = 32
            return [
                DiffusionEntry(dx: 1, dy: 0, weight: 8 / d), DiffusionEntry(dx: 2, dy: 0, weight: 4 / d),
                DiffusionEntry(dx: -2, dy: 1, weight: 2 / d), DiffusionEntry(dx: -1, dy: 1, weight: 4 / d),
                DiffusionEntry(dx: 0, dy: 1, weight: 8 / d), DiffusionEntry(dx: 1, dy: 1, weight: 4 / d),
                DiffusionEntry(dx: 2, dy: 1, weight: 2 / d),
            ]

        case .sierra:
            let d: Float = 32
            return [
                DiffusionEntry(dx: 1, dy: 0, weight: 5 / d), DiffusionEntry(dx: 2, dy: 0, weight: 3 / d),
                DiffusionEntry(dx: -2, dy: 1, weight: 2 / d), DiffusionEntry(dx: -1, dy: 1, weight: 4 / d),
                DiffusionEntry(dx: 0, dy: 1, weight: 5 / d), DiffusionEntry(dx: 1, dy: 1, weight: 4 / d),
                DiffusionEntry(dx: 2, dy: 1, weight: 2 / d),
                DiffusionEntry(dx: -1, dy: 2, weight: 2 / d), DiffusionEntry(dx: 0, dy: 2, weight: 3 / d),
                DiffusionEntry(dx: 1, dy: 2, weight: 2 / d),
            ]

        case .twoRowSierra:
            let d: Float = 16
            return [
                DiffusionEntry(dx: 1, dy: 0, weight: 4 / d), DiffusionEntry(dx: 2, dy: 0, weight: 3 / d),
                DiffusionEntry(dx: -2, dy: 1, weight: 1 / d), DiffusionEntry(dx: -1, dy: 1, weight: 2 / d),
                DiffusionEntry(dx: 0, dy: 1, weight: 3 / d), DiffusionEntry(dx: 1, dy: 1, weight: 2 / d),
                DiffusionEntry(dx: 2, dy: 1, weight: 1 / d),
            ]

        case .sierraLite:
            let d: Float = 4
            return [
                DiffusionEntry(dx: 1, dy: 0, weight: 2 / d),
                DiffusionEntry(dx: -1, dy: 1, weight: 1 / d),
                DiffusionEntry(dx: 0, dy: 1, weight: 1 / d),
            ]

        case .simple2D:
            let d: Float = 4
            return [
                DiffusionEntry(dx: 1, dy: 0, weight: 1 / d),
                DiffusionEntry(dx: 0, dy: 1, weight: 1 / d),
                DiffusionEntry(dx: 1, dy: 1, weight: 1 / d),
                DiffusionEntry(dx: -1, dy: 1, weight: 1 / d),
            ]

        case .stevensonArce:
            let d: Float = 200
            return [
                DiffusionEntry(dx: 2, dy: 0, weight: 32 / d),
                DiffusionEntry(dx: -3, dy: 1, weight: 12 / d), DiffusionEntry(dx: -1, dy: 1, weight: 26 / d),
                DiffusionEntry(dx: 1, dy: 1, weight: 30 / d), DiffusionEntry(dx: 3, dy: 1, weight: 16 / d),
                DiffusionEntry(dx: -2, dy: 2, weight: 12 / d), DiffusionEntry(dx: 0, dy: 2, weight: 26 / d),
                DiffusionEntry(dx: 2, dy: 2, weight: 12 / d),
                DiffusionEntry(dx: -3, dy: 3, weight: 5 / d), DiffusionEntry(dx: -1, dy: 3, weight: 12 / d),
                DiffusionEntry(dx: 1, dy: 3, weight: 12 / d), DiffusionEntry(dx: 3, dy: 3, weight: 5 / d),
            ]
        }
    }
    // swiftlint:enable function_body_length

    // MARK: - Binary Image Output

    private static func makeBinaryImage(from pixels: [Float], width: Int, height: Int) -> CGImage? {
        let count = width * height
        var rgba = [UInt8](repeating: 255, count: count * 4)

        for i in 0..<count {
            let v: UInt8 = pixels[i] > 127.5 ? 255 : 0
            rgba[i * 4] = v
            rgba[i * 4 + 1] = v
            rgba[i * 4 + 2] = v
            rgba[i * 4 + 3] = 255
        }

        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        return context.makeImage()
    }
}

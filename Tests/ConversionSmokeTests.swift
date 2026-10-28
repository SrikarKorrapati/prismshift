import AppKit
import AVFoundation
import CoreText
import ImageIO
import PDFKit
import UniformTypeIdentifiers

@main
struct ConversionSmokeTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw ConversionError.message("FAIL: \(message)") }
    }

    static func convert(_ id: ActionID, _ urls: [URL]) async throws -> [URL] {
        let action = FileAction(id: id, title: id.rawValue, subtitle: "", icon: "")
        let results = await ConversionService.shared.run(action: action, urls: urls)
        try require(!results.isEmpty, "\(id) returned no results")
        try require(results.allSatisfy { !$0.isError }, "\(id): \(results.map(\.message).joined(separator: "; "))")
        return results.compactMap(\.url)
    }

    static func imageDimensions(_ url: URL) throws -> (Int, Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ConversionError.message("Invalid output image: \(url.lastPathComponent)")
        }
        return (image.width, image.height)
    }

    @MainActor
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let folder = root.appendingPathComponent("work/verification-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let imageURL = folder.appendingPathComponent("Sample.png")
        let context = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0.45, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        let destination = CGImageDestinationCreateWithURL(imageURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        try require(CGImageDestinationFinalize(destination), "Fixture PNG")

        let pdfURL = folder.appendingPathComponent("Sample.pdf")
        var rect = CGRect(x: 0, y: 0, width: 144, height: 96)
        let pdfContext = CGContext(pdfURL as CFURL, mediaBox: &rect, nil)!
        for page in 1...2 {
            pdfContext.beginPDFPage(nil)
            pdfContext.setFillColor(CGColor(gray: 1, alpha: 1))
            pdfContext.fill(rect)
            pdfContext.textPosition = CGPoint(x: 10, y: 48)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "PrismShift page \(page)",
                attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black]))
            CTLineDraw(line, pdfContext)
            pdfContext.endPDFPage()
        }
        pdfContext.closePDF()
        let pdfOriginal = try Data(contentsOf: pdfURL)
        let imageOriginal = try Data(contentsOf: imageURL)

        let pdfActions = FileAction.actions(for: [pdfURL])
        try require(pdfActions.map(\.id).contains(.pdfJPEG) && pdfActions.map(\.id).contains(.pdfPNG), "PDF conversion actions")
        try require(Set(pdfActions.map(\.id)).count == pdfActions.count, "No duplicate PDF actions")
        for count in 2...8 {
            for index in 0..<count {
                try require(WheelGeometry.actionIndex(at: WheelGeometry.labelPoint(index: index, count: count), count: count) == index,
                            "Petal hit-testing \(count)/\(index)")
            }
            try require(WheelGeometry.actionIndex(at: WheelGeometry.center, count: count) == nil, "Centre does not convert")
            try require(WheelGeometry.actionIndex(at: CGPoint(x: 0, y: 0), count: count) == nil, "Outside does not convert")
        }
        print("PASS: dynamic action catalogue and rounded-petal hit testing")
        var gate = DragGestureGate(pasteboardCount: 1)
        try require(!gate.shouldOffer(pressed: true, point: .zero, pasteboardCount: 1, requested: true), "Shift-click does not open the wheel")
        try require(!gate.shouldOffer(pressed: true, point: CGPoint(x: 3, y: 0), pasteboardCount: 2, requested: true), "Drag threshold")
        try require(gate.shouldOffer(pressed: true, point: CGPoint(x: 20, y: 0), pasteboardCount: 2, requested: true), "Fresh file drag opens the wheel")
        _ = gate.shouldOffer(pressed: false, point: .zero, pasteboardCount: 2, requested: false)
        _ = gate.shouldOffer(pressed: true, point: .zero, pasteboardCount: 2, requested: true)
        try require(!gate.shouldOffer(pressed: true, point: CGPoint(x: 20, y: 0), pasteboardCount: 2, requested: true), "Stale drag payload is rejected")
        try require(!gate.shouldOffer(pressed: true, point: CGPoint(x: 20, y: 0), pasteboardCount: 3, requested: false), "Normal file drag is left alone")
        print("PASS: drag threshold, normal clicks and stale drag payloads")

        for id: ActionID in [.imagePNG, .imageJPEG, .imageTIFF, .imageHEIC, .imageBMP, .imageGIF] {
            let output = try await convert(id, [imageURL])[0]
            let dims = try imageDimensions(output)
            try require(dims.0 == 200 && dims.1 == 100, "Image dimensions for \(id)")
        }
        let resized = try await convert(.imageHalfSize, [imageURL])[0]
        let half = try imageDimensions(resized)
        try require(half.0 == 100 && half.1 == 50, "50% uses pixel dimensions")
        let imagePDF = try await convert(.imagePDF, [imageURL, imageURL])[0]
        try require(PDFDocument(url: imagePDF)?.pageCount == 2, "Images to PDF preserves selection count")
        print("PASS: PNG/JPEG/TIFF/HEIC/BMP/GIF, resize and images to PDF")

        let pngs = try await convert(.pdfPNG, [pdfURL])
        try require(pngs.count == 2, "All PDF pages exported")
        let dims = try imageDimensions(pngs[0])
        try require(dims.0 == 600 && dims.1 == 400, "PDF output is 300 DPI")
        let jpegs = try await convert(.pdfJPEG, [pdfURL])
        try require(jpegs.count == 2, "All JPEG pages exported")
        _ = try imageDimensions(jpegs[1])
        let text = try await convert(.pdfText, [pdfURL])[0]
        let textContent = try String(contentsOf: text, encoding: .utf8)
        try require(textContent.contains("PrismShift page 1") && textContent.contains("PrismShift page 2"), "PDF text extraction")
        let pages = try await convert(.pdfSplit, [pdfURL])
        try require(pages.count == 2 && pages.allSatisfy { PDFDocument(url: $0)?.pageCount == 1 }, "PDF split")
        let merged = try await convert(.pdfMerge, pages)[0]
        try require(PDFDocument(url: merged)?.pageCount == 2, "PDF merge")
        let repeatOutput = try await convert(.pdfPNG, [pdfURL])
        try require(repeatOutput[0] != pngs[0] && FileManager.default.fileExists(atPath: pngs[0].path), "Repeated conversions do not overwrite")
        let rotatedURL = folder.appendingPathComponent("Rotated.pdf")
        let rotated = PDFDocument(url: pdfURL)!
        rotated.page(at: 0)!.rotation = 90
        try require(rotated.write(to: rotatedURL), "Rotated fixture")
        let rotatedPNG = try await convert(.pdfPNG, [rotatedURL])[0]
        let rotatedDims = try imageDimensions(rotatedPNG)
        try require(rotatedDims.0 == 400 && rotatedDims.1 == 600, "PDF rotation retained")
        print("PASS: PDF JPG/PNG/text/split/merge, 300 DPI, rotation, collision handling")

        let broken = folder.appendingPathComponent("Unreadable.png")
        try Data("not an image".utf8).write(to: broken)
        let partial = await ConversionService.shared.run(action: FileAction(id: .imagePNG, title: "PNG", subtitle: "", icon: ""), urls: [imageURL, broken])
        try require(partial.count == 2 && partial.filter(\.isError).count == 1 && partial.compactMap(\.url).count == 1, "Partial batch failure preserves successful results")
        let scanned = await ConversionService.shared.run(action: FileAction(id: .pdfText, title: "TXT", subtitle: "", icon: ""), urls: [imagePDF])
        try require(scanned.first?.isError == true, "Image-only PDF reports that OCR is unavailable")
        let pdfAfter = try Data(contentsOf: pdfURL)
        let imageAfter = try Data(contentsOf: imageURL)
        try require(pdfAfter == pdfOriginal, "Original PDF untouched")
        try require(imageAfter == imageOriginal, "Original image untouched")
        print("PASS: partial failure, image-only PDF, unchanged originals")
        let media = root.appendingPathComponent("work/media-fixtures/Sample.mov")
        if FileManager.default.fileExists(atPath: media.path) {
            for id: ActionID in [.videoMP4, .videoMOV, .audioM4A] {
                let output = try await convert(id, [media])[0]
                let asset = AVURLAsset(url: output)
                let tracks = try await asset.loadTracks(withMediaType: id == .audioM4A ? .audio : .video)
                try require(!tracks.isEmpty, "Media output has playable tracks: \(id)")
            }
            print("PASS: playable MP4, MOV and M4A outputs")
        }
        try folder.path.write(to: root.appendingPathComponent("work/last-verification.txt"), atomically: true, encoding: .utf8)
        print("Fixtures: \(folder.path)")
    }
}

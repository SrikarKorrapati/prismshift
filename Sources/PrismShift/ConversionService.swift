import AppKit
import AVFoundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

struct ConversionResult: Identifiable, Sendable {
    let id = UUID()
    let message: String
    let url: URL?
    let isError: Bool
}

/// Serial worker keeps PDF rendering and image encoding off the UI thread.
actor ConversionService {
    static let shared = ConversionService()

    func run(action: FileAction, urls: [URL]) async -> [ConversionResult] {
        guard !urls.isEmpty else { return [failure("No files were selected.")] }
        if action.id == .pdfMerge || action.id == .imagePDF {
            do {
                let output = action.id == .pdfMerge ? try mergePDFs(urls) : try imagesToPDF(urls)
                return [success(output)]
            } catch { return [failure(error.localizedDescription)] }
        }
        var results: [ConversionResult] = []
        for url in urls {
            do {
                switch action.id {
                case .imagePNG: results.append(success(try convertImage(url, type: .png)))
                case .imageJPEG: results.append(success(try convertImage(url, type: .jpeg)))
                case .imageTIFF: results.append(success(try convertImage(url, type: .tiff)))
                case .imageHEIC: results.append(success(try convertImage(url, type: .heic)))
                case .imageBMP: results.append(success(try convertImage(url, type: .bmp)))
                case .imageGIF: results.append(success(try convertImage(url, type: .gif)))
                case .imageHalfSize: results.append(success(try convertImage(url, type: .png, scale: 0.5)))
                case .pdfPNG: results += try renderPDF(url, type: .png).map(success)
                case .pdfJPEG: results += try renderPDF(url, type: .jpeg).map(success)
                case .pdfText:
                    let document = try readPDF(url)
                    guard let text = document.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw ConversionError.message("This PDF has no selectable text. OCR is not available.")
                    }
                    let output = uniqueOutputURL(for: url, suffix: "text", ext: "txt")
                    try text.write(to: output, atomically: true, encoding: .utf8)
                    results.append(success(output))
                case .pdfSplit: results += try splitPDF(url).map(success)
                case .videoMP4, .videoMOV, .audioM4A:
                    results.append(success(try await exportMedia(url, action: action.id)))
                case .reveal, .copyPath, .imagePDF, .pdfMerge: break
                }
            } catch {
                results.append(failure("\(url.lastPathComponent): \(error.localizedDescription)"))
            }
        }
        return results
    }

    private func readPDF(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw ConversionError.message("Could not read this PDF.")
        }
        guard !document.isLocked else { throw ConversionError.message("Unlock the PDF before converting it.") }
        return document
    }

    private func readImage(_ url: URL, scale: Double = 1) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw ConversionError.message("Could not read this image.")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(Double(max(width, height)) * scale))
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ConversionError.message("Could not decode this image.")
        }
        return image
    }

    private func writeImage(_ image: CGImage, to output: URL, type: UTType) throws {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw ConversionError.message("\(type.preferredFilenameExtension?.uppercased() ?? "This format") encoding is unavailable on this Mac.")
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.9,
            kCGImagePropertyDPIWidth: 300,
            kCGImagePropertyDPIHeight: 300
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.message("Image encoding failed.") }
        try (data as Data).write(to: output, options: .atomic)
    }

    private func convertImage(_ url: URL, type: UTType, scale: Double = 1) throws -> URL {
        let image = try readImage(url, scale: scale)
        let ext = type == .jpeg ? "jpg" : (type.preferredFilenameExtension ?? "png")
        let output = uniqueOutputURL(for: url, suffix: scale < 1 ? "half" : ext.uppercased(), ext: ext)
        try writeImage(image, to: output, type: type)
        return output
    }

    private func renderPDF(_ url: URL, type: UTType) throws -> [URL] {
        let document = try readPDF(url)
        let ext = type == .jpeg ? "jpg" : "png"
        let folder = try outputFolder(for: url, suffix: ext.uppercased())
        var outputs: [URL] = []
        do {
            for index in 0..<document.pageCount {
                try autoreleasepool {
                    guard let page = document.page(at: index)?.pageRef else {
                        throw ConversionError.message("Could not read page \(index + 1).")
                    }
                    let box = page.getBoxRect(.cropBox)
                    let rotated = abs(page.rotationAngle) % 180 == 90
                    let width = Int(ceil((rotated ? box.height : box.width) * 300 / 72))
                    let height = Int(ceil((rotated ? box.width : box.height) * 300 / 72))
                    guard width > 0, height > 0, Double(width) * Double(height) <= 80_000_000,
                          let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                        throw ConversionError.message("Page \(index + 1) is too large to render safely at 300 DPI.")
                    }
                    let rect = CGRect(x: 0, y: 0, width: width, height: height)
                    context.setFillColor(CGColor(gray: 1, alpha: 1))
                    context.fill(rect)
                    context.concatenate(page.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
                    context.drawPDFPage(page)
                    guard let image = context.makeImage() else { throw ConversionError.message("Page rendering failed.") }
                    let output = folder.appendingPathComponent(String(format: "Page %03d.%@", index + 1, ext))
                    try writeImage(image, to: output, type: type)
                    outputs.append(output)
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return outputs
    }

    private func splitPDF(_ url: URL) throws -> [URL] {
        let document = try readPDF(url)
        let folder = try outputFolder(for: url, suffix: "pages")
        var outputs: [URL] = []
        do {
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { throw ConversionError.message("Could not read a PDF page.") }
                let single = PDFDocument()
                single.insert(page, at: 0)
                let output = folder.appendingPathComponent(String(format: "Page %03d.pdf", index + 1))
                guard let data = single.dataRepresentation() else { throw ConversionError.message("Could not write this PDF.") }
                try data.write(to: output, options: .atomic)
                outputs.append(output)
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return outputs
    }

    private func mergePDFs(_ urls: [URL]) throws -> URL {
        let merged = PDFDocument()
        for url in urls {
            let document = try readPDF(url)
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { throw ConversionError.message("Could not read a PDF page.") }
                merged.insert(page, at: merged.pageCount)
            }
        }
        let output = uniqueOutputURL(for: urls[0], suffix: "merged", ext: "pdf")
        guard let data = merged.dataRepresentation() else { throw ConversionError.message("Could not create the merged PDF.") }
        try data.write(to: output, options: .atomic)
        return output
    }

    private func imagesToPDF(_ urls: [URL]) throws -> URL {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw ConversionError.message("Could not create the PDF.")
        }
        for url in urls {
            let image = try readImage(url)
            let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.beginPDFPage([kCGPDFContextMediaBox: NSData(bytes: [rect], length: MemoryLayout<CGRect>.size)] as CFDictionary)
            context.draw(image, in: rect)
            context.endPDFPage()
        }
        context.closePDF()
        let output = uniqueOutputURL(for: urls[0], suffix: "converted", ext: "pdf")
        try (data as Data).write(to: output, options: .atomic)
        return output
    }

    private func exportMedia(_ url: URL, action: ActionID) async throws -> URL {
        let audioOnly = action == .audioM4A
        let type: AVFileType = audioOnly ? .m4a : (action == .videoMOV ? .mov : .mp4)
        let ext = audioOnly ? "m4a" : (action == .videoMOV ? "mov" : "mp4")
        let asset = AVURLAsset(url: url)
        if audioOnly, try await asset.loadTracks(withMediaType: .audio).isEmpty {
            throw ConversionError.message("This file has no compatible audio track.")
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: audioOnly ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality),
              session.supportedFileTypes.contains(type) else {
            throw ConversionError.message("macOS cannot convert this media format.")
        }
        let output = uniqueOutputURL(for: url, suffix: ext.uppercased(), ext: ext)
        session.outputURL = output
        session.outputFileType = type
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { continuation.resume() }
        }
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw session.error ?? ConversionError.message("Media conversion failed.")
        }
        return output
    }

    private func outputFolder(for input: URL, suffix: String) throws -> URL {
        let folder = uniqueOutputURL(for: input, suffix: suffix, ext: "")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    private func uniqueOutputURL(for input: URL, suffix: String, ext: String) -> URL {
        let directory = input.deletingLastPathComponent()
        let stem = input.deletingPathExtension().lastPathComponent + "-" + suffix
        var counter = 1
        while true {
            let name = stem + (counter == 1 ? "" : "-\(counter)") + (ext.isEmpty ? "" : ".\(ext)")
            let candidate = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    private func success(_ url: URL) -> ConversionResult {
        ConversionResult(message: "Created \(url.lastPathComponent)", url: url, isError: false)
    }
    private func failure(_ message: String) -> ConversionResult {
        ConversionResult(message: message, url: nil, isError: true)
    }
}

enum ConversionError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

import Foundation

enum FileKind: String { case image, pdf, video, audio, document, unknown }
enum WheelMode: String { case convert, tools, files }

enum ActionID: String, CaseIterable, Identifiable, Sendable {
    case imagePNG, imageJPEG, imageTIFF, imageHEIC, imageBMP, imageGIF, imagePDF, imageHalfSize
    case pdfPNG, pdfJPEG, pdfText, pdfSplit, pdfMerge
    case videoMP4, videoMOV, audioM4A
    case reveal, copyPath
    var id: String { rawValue }
}

struct FileAction: Identifiable, Sendable {
    let id: ActionID
    let title: String
    let subtitle: String
    let icon: String

    static let reveal = FileAction(id: .reveal, title: "REVEAL", subtitle: "Show in Finder", icon: "finder")
    static let copyPath = FileAction(id: .copyPath, title: "PATH", subtitle: "Copy file paths", icon: "link")
    static let resize = FileAction(id: .imageHalfSize, title: "RESIZE", subtitle: "Reduce dimensions to 50%", icon: "arrow.down.right.and.arrow.up.left")
    static let split = FileAction(id: .pdfSplit, title: "SPLIT", subtitle: "Save each page as a PDF", icon: "square.split.2x1")
    static let merge = FileAction(id: .pdfMerge, title: "MERGE", subtitle: "Combine PDFs in selection order", icon: "square.stack")

    static func actions(for urls: [URL], mode: WheelMode = .convert) -> [FileAction] {
        guard !urls.isEmpty else { return [] }
        if mode == .files { return [reveal, copyPath] }
        let kinds = Set(urls.map(FileInspector.kind))
        guard kinds.count == 1, let kind = kinds.first else { return [reveal, copyPath] }
        if mode == .tools {
            switch kind {
            case .image: return [resize, reveal, copyPath]
            case .pdf: return (urls.count > 1 ? [merge, split] : [split]) + [reveal, copyPath]
            default: return [reveal, copyPath]
            }
        }
        switch kind {
        case .image:
            return [
                FileAction(id: .imageJPEG, title: "JPG", subtitle: "Convert to JPEG", icon: "photo"),
                FileAction(id: .imagePNG, title: "PNG", subtitle: "Convert to PNG", icon: "photo"),
                FileAction(id: .imageHEIC, title: "HEIC", subtitle: "Convert to HEIC", icon: "photo"),
                FileAction(id: .imageTIFF, title: "TIFF", subtitle: "Convert to TIFF", icon: "photo"),
                FileAction(id: .imageBMP, title: "BMP", subtitle: "Convert to BMP", icon: "photo"),
                FileAction(id: .imageGIF, title: "GIF", subtitle: "Convert first frame to GIF", icon: "photo"),
                FileAction(id: .imagePDF, title: "PDF", subtitle: "Create a PDF, one page per image", icon: "doc"),
                resize
            ]
        case .pdf:
            return [
                FileAction(id: .pdfJPEG, title: "JPG", subtitle: "Export every page as JPEG at 300 DPI", icon: "photo"),
                FileAction(id: .pdfPNG, title: "PNG", subtitle: "Export every page as PNG at 300 DPI", icon: "photo"),
                FileAction(id: .pdfText, title: "TXT", subtitle: "Extract selectable text (no OCR)", icon: "doc.text"),
                split
            ] + (urls.count > 1 ? [merge] : []) + [reveal]
        case .video:
            return [
                FileAction(id: .videoMP4, title: "MP4", subtitle: "Export compatible video as MP4", icon: "film"),
                FileAction(id: .videoMOV, title: "MOV", subtitle: "Export compatible video as QuickTime", icon: "film"),
                FileAction(id: .audioM4A, title: "M4A", subtitle: "Extract audio as M4A", icon: "waveform"),
                reveal
            ]
        case .audio:
            return [FileAction(id: .audioM4A, title: "M4A", subtitle: "Convert compatible audio to M4A", icon: "waveform"), reveal]
        case .document, .unknown:
            return [reveal, copyPath]
        }
    }
}

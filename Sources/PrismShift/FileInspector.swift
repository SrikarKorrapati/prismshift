import Foundation

enum FileInspector {
    static func kind(for url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()

        if ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "bmp"].contains(ext) {
            return .image
        }

        if ext == "pdf" {
            return .pdf
        }

        if ["mov", "mp4", "m4v", "mkv", "avi", "webm"].contains(ext) {
            return .video
        }

        if ["mp3", "m4a", "wav", "aiff", "flac", "aac"].contains(ext) {
            return .audio
        }

        if ["doc", "docx", "pages", "rtf", "txt", "md", "ppt", "pptx", "xls", "xlsx"].contains(ext) {
            return .document
        }

        return .unknown
    }

    static func displayName(for urls: [URL]) -> String {
        if urls.isEmpty {
            return "No files selected"
        }

        if urls.count == 1 {
            return urls[0].lastPathComponent
        }

        return "\(urls.count) files selected"
    }
}

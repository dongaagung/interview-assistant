import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Reads a CV into plain text for the profile.
enum ResumeImport {
    enum Failure: LocalizedError {
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let name): "Couldn't read text from \(name). Try a PDF or Word file."
            }
        }
    }

    static let contentTypes: [UTType] = [
        .pdf, .plainText, .rtf,
        UTType("org.openxmlformats.wordprocessingml.document") ?? .data,
    ]

    /// PDF, Word (.docx), RTF or plain text. Email addresses and phone
    /// numbers are removed: they would go to the API with every hint and
    /// don't help answer anything.
    static func text(from url: URL) throws -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let raw: String?
        if url.pathExtension.lowercased() == "pdf" {
            raw = PDFDocument(url: url)?.string
        } else if url.pathExtension.lowercased() == "txt" || url.pathExtension.lowercased() == "md" {
            raw = try? String(contentsOf: url, encoding: .utf8)
        } else {
            raw = (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string
        }
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.unreadable(url.lastPathComponent)
        }
        return tidy(redactContactDetails(raw))
    }

    static func redactContactDetails(_ text: String) -> String {
        text
            .replacing(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/, with: "[email]")
            // International (+62 823 …) or local (0823-…) numbers with 9+ digits.
            .replacing(/(?:\+\d{1,3}|\b0)[\d \-().]{7,}\d/) { match in
                match.output.filter(\.isNumber).count >= 9 ? "[phone]" : String(match.output)
            }
    }

    /// Collapses the runs of blank lines and trailing spaces PDF text has.
    private static func tidy(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .replacing(/\n{3,}/, with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

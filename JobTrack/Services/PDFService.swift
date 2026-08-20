import Foundation
import PDFKit
import CoreText
import CoreGraphics

/// Reads text from PDFs and exports text as a PDF. Cross-platform (PDFKit).
enum PDFService {

    /// Extracts plain text from PDF bytes. Returns "" if the PDF has no text
    /// layer (e.g. a scanned image — use OCR in that case).
    static func extractText(from data: Data) -> String {
        guard let document = PDFDocument(data: data) else { return "" }
        return document.string ?? ""
    }

    /// Renders a plain-text string into a simple, paginated A4 PDF.
    /// Used to export generated cover letters.
    static func makePDF(from text: String, title: String = "Lettre de motivation") -> Data {
        let pageWidth: CGFloat = 595.2   // A4 @ 72 dpi
        let pageHeight: CGFloat = 841.8
        let margin: CGFloat = 48
        let contentRect = CGRect(
            x: margin, y: margin,
            width: pageWidth - margin * 2,
            height: pageHeight - margin * 2
        )

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let attributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 12),
            .paragraphStyle: paragraph,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var currentRange = CFRange(location: 0, length: 0)
        let totalLength = attributed.length

        repeat {
            context.beginPDFPage(nil)
            // Flip coordinates so text draws top-to-bottom.
            context.textMatrix = .identity
            context.translateBy(x: 0, y: pageHeight)
            context.scaleBy(x: 1, y: -1)

            let path = CGPath(rect: CGRect(
                x: contentRect.minX,
                y: pageHeight - contentRect.maxY,
                width: contentRect.width,
                height: contentRect.height
            ), transform: nil)

            let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)
            CTFrameDraw(frame, context)

            let visible = CTFrameGetVisibleStringRange(frame)
            currentRange = CFRange(location: visible.location + visible.length, length: 0)

            context.endPDFPage()
        } while currentRange.location < totalLength

        context.closePDF()
        return data as Data
    }
}

#if canImport(UIKit)
import UIKit
typealias PlatformFont = UIFont
#elseif canImport(AppKit)
import AppKit
typealias PlatformFont = NSFont
#endif

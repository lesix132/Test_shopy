import Foundation
import Vision
import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Extracts text from images (screenshots of offers) via the Vision framework.
enum OCRService {

    enum OCRError: LocalizedError {
        case invalidImage
        case recognitionFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidImage:            return "Image invalide."
            case .recognitionFailed(let m): return "Échec de l'OCR : \(m)"
            }
        }
    }

    /// Recognizes text in a `CGImage`. French + English, accurate mode.
    static func recognizeText(in cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["fr-FR", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                }
            }
        }
    }

    /// Recognizes text from raw image bytes (e.g. a pasted screenshot).
    static func recognizeText(inImageData data: Data) async throws -> String {
        guard let cgImage = Self.cgImage(from: data) else { throw OCRError.invalidImage }
        return try await recognizeText(in: cgImage)
    }

    private static func cgImage(from data: Data) -> CGImage? {
        #if canImport(UIKit)
        return UIImage(data: data)?.cgImage
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #else
        return nil
        #endif
    }
}

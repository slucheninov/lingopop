import Foundation
import Vision

enum ScreenOCRError: UserFacingError {
    case noTextFound
    case recognitionFailed(Error)

    /// Shown instead of the plain `noTextFound` summary when vision-capable
    /// providers are available for a Retry.
    static let noTextFoundRetryHint = String(localized: "No text found in the selected area. Try a larger selection or use Retry to send the image to AI.")

    var userSummary: String {
        switch self {
        case .noTextFound:
            return String(localized: "No text found in the selected area. Try a larger selection.")
        case .recognitionFailed(let error):
            return String(localized: "Text recognition failed: \(error.localizedDescription)")
        }
    }
}

enum ScreenOCR {

    /// Recognises text in `image` using the Vision framework.
    /// Observations are sorted top-to-bottom (highest Y first in Vision's normalised coords).
    static func recognize(image: CGImage) async throws -> String {
        // Vision's `perform` is synchronous; run it off the caller's executor.
        try await Task.detached(priority: .userInitiated) {
            try performRecognition(image: image)
        }.value
    }

    private static func performRecognition(image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw ScreenOCRError.recognitionFailed(error)
        }
        let text = (request.results ?? [])
            .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        if text.isEmpty { throw ScreenOCRError.noTextFound }
        return text
    }
}

import Foundation
import Vision

enum ScreenOCRError: LocalizedError {
    case noTextFound
    case recognitionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noTextFound:
            return "No text was recognized in the selected area."
        case .recognitionFailed(let error):
            return "Text recognition failed: \(error.localizedDescription)"
        }
    }
}

enum ScreenOCR {

    /// Recognises text in `image` using the Vision framework.
    /// Observations are sorted top-to-bottom (highest Y first in Vision's normalised coords).
    static func recognize(image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            // The completion handler and a thrown `perform` can both report; guard against double resume.
            let lock = NSLock()
            var resumed = false
            func finish(_ result: Result<String, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { req, error in
                    if let error {
                        finish(.failure(ScreenOCRError.recognitionFailed(error)))
                        return
                    }
                    let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                    let text = observations
                        .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n")
                    if text.isEmpty {
                        finish(.failure(ScreenOCRError.noTextFound))
                    } else {
                        finish(.success(text))
                    }
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    finish(.failure(ScreenOCRError.recognitionFailed(error)))
                }
            }
        }
    }
}

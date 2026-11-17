import CoreGraphics
import Foundation
import ImageIO
import Vision

/// On-device OCR of a screenshot into text lines (PLAN_M4 M4-9 §2). No network; the image isn't kept.
enum KoreanTextExtractor {
    enum ExtractError: LocalizedError {
        case unreadableImage

        var errorDescription: String? { "That image couldn't be read." }
    }

    /// Recognised lines, top to bottom. Runs off the main thread.
    static func lines(fromImageData data: Data) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { throw ExtractError.unreadableImage }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ko-KR", "en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            let observations = request.results ?? []
            // Vision's origin is bottom-left: sort by descending y for reading order.
            return observations
                .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
                .compactMap { $0.topCandidates(1).first?.string }
        }.value
    }
}

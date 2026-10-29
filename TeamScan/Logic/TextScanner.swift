import UIKit
import Vision

/// One line of recognized text. `rect` is normalized (0…1) with the origin at the top left.
struct OCRLine: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let rect: CGRect

    var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
}

enum TextScanner {
    enum ScanError: LocalizedError {
        case noImage
        var errorDescription: String? { L("Das Bild konnte nicht gelesen werden.", "The image could not be read.") }
    }

    /// Recognizes German and English text on the device (no internet needed).
    static func recognize(_ image: UIImage) async throws -> [OCRLine] {
        guard let cg = image.preparedForOCR().cgImage else { throw ScanError.noImage }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "de-DE"), Locale.Language(identifier: "en-US")]
        request.usesLanguageCorrection = false
        let observations = try await request.perform(on: cg)
        return observations.compactMap { obs in
            guard let text = obs.topCandidates(1).first?.string else { return nil }
            let r = obs.boundingBox.cgRect
            // Vision uses a bottom-left origin – flip to top-left.
            return OCRLine(text: text, rect: CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height))
        }
        .sorted { ($0.rect.minY, $0.rect.minX) < ($1.rect.minY, $1.rect.minX) }
    }
}

extension UIImage {
    /// Redraws the image upright and limits its size.
    func preparedForOCR(maxSide: CGFloat = 2400) -> UIImage {
        let longest = max(size.width, size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

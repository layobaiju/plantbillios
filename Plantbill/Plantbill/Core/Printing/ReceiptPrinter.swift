import SwiftUI
import UIKit

/// Prints via AirPrint — the standard iOS print system. The printer just
/// needs to be AirPrint-capable and on the same Wi-Fi network; no pairing,
/// no vendor app, no extra hardware. The system print sheet itself handles
/// discovering and selecting the printer.
///
/// Android prints over classic Bluetooth, which iPhones cannot use (see
/// `PrinterTransport`), so the receipt's *content* matches Android's exactly
/// while the route to paper is Apple's.
enum ReceiptPrinter {
    /// - Parameter completion: `printed` is true once the job was handed to a
    ///   printer; `failed` is true only for a real error — cancelling the
    ///   print sheet is neither.
    @MainActor
    static func print(_ data: ReceiptPrintData, completion: ((_ printed: Bool, _ failed: Bool) -> Void)? = nil) {
        let renderer = ImageRenderer(content: ReceiptPrintView(data: data))
        renderer.scale = 3
        guard let image = renderer.uiImage else {
            completion?(false, true)
            return
        }

        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .grayscale
        info.jobName = "Receipt"

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = image
        controller.present(animated: true) { _, completed, error in
            completion?(completed, error != nil)
        }
    }

    /// The whole bill for printing. Android fetches the bill's detail first,
    /// because the shop header — address, phone, logo — only lives there. With
    /// no signal it prints what the app already has rather than nothing.
    @MainActor
    static func receipt(forBillId id: UUID, fallback: ReceiptPrintData) async -> ReceiptPrintData {
        guard let detail: BillDetail = try? await APIClient.shared.send(
            Endpoint(path: "bills/\(id.uuidString.lowercased())")
        ) else {
            return fallback
        }
        return await receipt(for: detail)
    }

    @MainActor
    static func receipt(for detail: BillDetail) async -> ReceiptPrintData {
        var data = detail.receiptData
        data.logo = await fetchLogo(detail.businessLogoUrl)
        return data
    }

    /// Fails soft, as Android's does: a logo is decoration, and a receipt that
    /// won't print because an image didn't load is a real problem in front of
    /// a waiting customer. Offline, 404, a corrupt file or a slow server all
    /// just print without it.
    private static func fetchLogo(_ raw: String?) async -> UIImage? {
        guard let url = MediaURL.resolve(raw) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        return UIImage(data: data)
    }
}

import Foundation

/// Keeps "sales till now" and the customer list saved on the phone even when
/// nobody opens those tabs while there's signal. A cashier can bill all
/// morning without once looking at Sales, lose the connection at noon, and
/// still see the morning's takings.
///
/// Refreshed when the app opens, when it comes back to the front, and after
/// every saved bill. It makes exactly the requests the Sales and Customers
/// screens make — the saved copies are looked up by request, so anything else
/// would save files nobody ever reads.
@MainActor
enum OfflinePrefetch {
    private static var inFlight: Task<Void, Never>?

    static func refresh() {
        guard inFlight == nil, BusinessProfile.shared.userId != nil else { return }
        inFlight = Task {
            defer { inFlight = nil }
            let today = ShopCalendar.apiDateString(ShopCalendar.today())
            let _: Cached<DaySummary>? = try? await APIClient.shared.sendCached(
                Endpoint(path: "bills/summary/today", queryItems: SalesViewModel.summaryQuery(dateString: today, staffId: nil))
            )
            let _: Cached<BillListPage>? = try? await APIClient.shared.sendCached(
                Endpoint(path: "bills", queryItems: SalesViewModel.billsQuery(dateString: today, offset: 0, staffId: nil))
            )
            let _: Cached<[Customer]>? = try? await APIClient.shared.sendCached(
                Endpoint(path: "customers")
            )
            let _: Cached<BillListPage>? = try? await APIClient.shared.sendCached(
                Endpoint(path: "bills", queryItems: DuesViewModel.duesQuery)
            )
        }
    }
}

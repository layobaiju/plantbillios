import Combine
import SwiftUI

/// Read-only cross-shop credit ledger for the multi-shop owner, mirroring
/// Android's `OwnerDuesScreen`: total outstanding across every shop, a row per
/// shop, and a drill-in to the customers behind one shop's balance.
///
/// Deliberately read-only — settling a due goes through the shop's own Dues
/// screen so it still passes the manager approval workflow.
@MainActor
final class OwnerDuesViewModel: ObservableObject {
    @Published private(set) var overview: OwnerDuesOverview?
    @Published private(set) var isLoading = true
    @Published private(set) var loadError: String?

    /// Per-shop customer breakdown, loaded lazily when a shop is expanded.
    @Published private(set) var customersByShop: [UUID: [CustomerDueRow]] = [:]
    @Published private(set) var loadingShopId: UUID?
    @Published var expandedShopId: UUID?

    func load() async {
        isLoading = true
        loadError = nil
        do {
            overview = try await APIClient.shared.send(Endpoint(path: "owner/dues"))
            isLoading = false
        } catch let error as APIError {
            isLoading = false
            loadError = error.userMessage
        } catch {
            isLoading = false
            loadError = APIError.unknown.userMessage
        }
    }

    func toggle(_ shopId: UUID) async {
        if expandedShopId == shopId {
            expandedShopId = nil
            return
        }
        expandedShopId = shopId
        guard customersByShop[shopId] == nil else { return }
        loadingShopId = shopId
        let rows: [CustomerDueRow]? = try? await APIClient.shared.send(
            Endpoint(path: "owner/shops/\(shopId)/dues")
        )
        customersByShop[shopId] = rows ?? []
        loadingShopId = nil
    }
}

struct OwnerDuesView: View {
    @StateObject private var viewModel = OwnerDuesViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: PlantbillSpacing.lg) {
                if viewModel.isLoading {
                    LoadingStateView(message: "Loading dues…")
                } else if let error = viewModel.loadError {
                    ErrorStateView(message: LocalizedStringKey(error)) {
                        Task { await viewModel.load() }
                    }
                } else if let overview = viewModel.overview {
                    totalCard(overview)
                    if (overview.shops ?? []).isEmpty {
                        EmptyStateView(
                            icon: "checkmark.circle",
                            title: "Nothing outstanding",
                            message: "No shop has money owed right now."
                        )
                    } else {
                        ForEach(overview.shops ?? []) { shop in
                            shopCard(shop)
                        }
                    }
                }
            }
            .padding(PlantbillSpacing.lg)
        }
        .background(PlantbillColor.background)
        .navigationTitle("Dues")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    private func totalCard(_ overview: OwnerDuesOverview) -> some View {
        PlantbillCard {
            VStack(alignment: .leading, spacing: PlantbillSpacing.xs) {
                Text("Total outstanding")
                    .font(PlantbillTypography.body)
                    .foregroundStyle(PlantbillColor.textSecondary)
                Text(overview.totalOutstandingMoney.format())
                    .font(PlantbillTypography.largeTitle)
                    .foregroundStyle(PlantbillColor.error)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func shopCard(_ shop: ShopDueRow) -> some View {
        PlantbillCard {
            VStack(alignment: .leading, spacing: PlantbillSpacing.sm) {
                Button {
                    Task { await viewModel.toggle(shop.shopId) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shop.shopName)
                                .font(PlantbillTypography.bodyEmphasized)
                                .foregroundStyle(PlantbillColor.textPrimary)
                            Text("\(shop.customerCount) customer\(shop.customerCount == 1 ? "" : "s") · \(shop.billCount) bill\(shop.billCount == 1 ? "" : "s")")
                                .font(PlantbillTypography.caption)
                                .foregroundStyle(PlantbillColor.textSecondary)
                        }
                        Spacer()
                        Text(shop.outstandingMoney.format())
                            .font(PlantbillTypography.bodyEmphasized)
                            .foregroundStyle(PlantbillColor.error)
                        Image(systemName: viewModel.expandedShopId == shop.shopId ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(PlantbillColor.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if viewModel.expandedShopId == shop.shopId {
                    Divider()
                    if viewModel.loadingShopId == shop.shopId {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        let rows = viewModel.customersByShop[shop.shopId] ?? []
                        if rows.isEmpty {
                            Text("No customers owe this shop.")
                                .font(PlantbillTypography.caption)
                                .foregroundStyle(PlantbillColor.textSecondary)
                        } else {
                            ForEach(rows) { row in
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(row.name)
                                            .font(PlantbillTypography.body)
                                            .foregroundStyle(PlantbillColor.textPrimary)
                                        if let phone = row.phone, !phone.isEmpty {
                                            Text(phone)
                                                .font(PlantbillTypography.caption)
                                                .foregroundStyle(PlantbillColor.textSecondary)
                                        }
                                    }
                                    Spacer()
                                    Text(row.outstandingMoney.format())
                                        .font(PlantbillTypography.body)
                                        .foregroundStyle(PlantbillColor.error)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

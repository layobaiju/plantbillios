import SwiftUI

/// The billing screen, laid out like Android's `BillScreen`: a search box with
/// the mic inside it, the category chips with the blocks/list switch at their
/// end, the catalogue, a round cart button (item-count badge) above a round
/// quick-add button in the corner, and a "Held bills (N)" bar along the bottom.
struct BillView: View {
    @StateObject private var viewModel = BillingViewModel()
    /// A device setting, deliberately outside the bill's state — Android found
    /// that keeping it in the bill made it reset after every sale.
    @AppStorage("product_view_mode") private var viewModeRaw = ProductViewMode.grid.rawValue

    @State private var showingCartReview = false
    @State private var showingQuickAdd = false
    @State private var showingHeldBills = false
    /// A sheet can't be presented while another is still closing, so the
    /// review opens from the closing sheet's `onDismiss` instead.
    @State private var reviewAfterSheet = false
    @FocusState private var searchFocused: Bool

    private var viewMode: ProductViewMode { ProductViewMode(rawValue: viewModeRaw) ?? .grid }

    var body: some View {
        NavigationStack {
            Group {
                if case .success(let bill) = viewModel.checkoutState {
                    BillSuccessView(bill: bill) {
                        viewModel.startNewBill()
                    }
                } else {
                    browsingContent
                }
            }
            .navigationTitle("Bill")
            .navigationBarTitleDisplayMode(.inline)
            .background(PlantbillColor.background)
            .task { await viewModel.loadProducts() }
            .notificationBell()
            .sheet(isPresented: $showingCartReview) {
                CartReviewSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showingQuickAdd, onDismiss: openReviewIfQueued) {
                QuickAddSheet(viewModel: viewModel) {
                    reviewAfterSheet = true
                }
            }
            .sheet(isPresented: $showingHeldBills, onDismiss: openReviewIfQueued) {
                HeldBillsSheet(viewModel: viewModel) { held in
                    viewModel.resume(held)
                    reviewAfterSheet = true
                    showingHeldBills = false
                }
            }
        }
    }

    private func openReviewIfQueued() {
        guard reviewAfterSheet else { return }
        reviewAfterSheet = false
        showingCartReview = true
    }

    private var browsingContent: some View {
        VStack(spacing: 0) {
            searchField
            chipsRow
            if viewModel.isShowingCachedProducts {
                // Says plainly what still works, rather than leaving the
                // cashier wondering whether the prices are stale.
                Text("Showing saved plants. You can still bill and hold it — it saves when you're back online.")
                    .font(PlantbillTypography.caption)
                    .foregroundStyle(PlantbillColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, PlantbillSpacing.md)
                    .padding(.bottom, PlantbillSpacing.xs)
            }
            catalog
        }
        .overlay(alignment: .bottomTrailing) { cornerButtons }
        .safeAreaInset(edge: .bottom, spacing: 0) { heldBillsBar }
        .overlay(alignment: .top) { toastView }
        .animation(.easeInOut(duration: 0.2), value: viewModel.toast)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.cartLines.isEmpty)
    }

    // MARK: Search

    /// Android's OutlinedTextField: magnifier in front, the mic inside the box
    /// at its end.
    private var searchField: some View {
        HStack(spacing: PlantbillSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PlantbillColor.textSecondary)

            ZStack(alignment: .leading) {
                if viewModel.searchText.isEmpty {
                    Text("Search products")
                        .font(PlantbillTypography.body)
                        .foregroundStyle(PlantbillColor.textSecondary)
                        .allowsHitTesting(false)
                }
                TextField("", text: $viewModel.searchText)
                    .font(PlantbillTypography.body)
                    .foregroundStyle(PlantbillColor.textPrimary)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            VoiceSearchButton(
                onResults: { viewModel.onVoiceTranscript($0) },
                onUnavailable: { viewModel.showVoiceUnavailable() }
            )
        }
        .padding(.leading, PlantbillSpacing.md)
        .frame(minHeight: PlantbillSpacing.primaryActionHeight)
        .background(
            RoundedRectangle(cornerRadius: PlantbillSpacing.controlCornerRadius)
                .fill(PlantbillColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PlantbillSpacing.controlCornerRadius)
                .stroke(searchFocused ? PlantbillColor.green : PlantbillColor.border, lineWidth: searchFocused ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { searchFocused = true }
        .padding(.horizontal, PlantbillSpacing.md)
        .padding(.top, PlantbillSpacing.sm)
    }

    // MARK: Categories + layout switch

    private var chipsRow: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PlantbillSpacing.sm) {
                    FilterChip(title: "All", isSelected: viewModel.selectedCategory == nil) {
                        viewModel.selectedCategory = nil
                    }
                    ForEach(viewModel.categories, id: \.self) { category in
                        FilterChip(verbatim: category, isSelected: viewModel.selectedCategory == category) {
                            viewModel.selectedCategory = category
                        }
                    }
                }
                .padding(.horizontal, PlantbillSpacing.md)
                .padding(.vertical, PlantbillSpacing.sm)
            }

            ProductViewToggle(mode: viewMode) { viewModeRaw = $0.rawValue }
                .padding(.trailing, PlantbillSpacing.xs)
        }
    }

    // MARK: Catalogue

    @ViewBuilder
    private var catalog: some View {
        switch viewModel.catalogState {
        case .loading:
            LoadingStateView(message: "Loading your products…")
        case .error(let message):
            ErrorStateView(message: LocalizedStringKey(message)) {
                Task { await viewModel.loadProducts() }
            }
        case .loaded:
            let products = viewModel.filteredProducts
            if products.isEmpty {
                if viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    EmptyStateView(
                        icon: "leaf",
                        title: "No products",
                        message: "Add products in the Products tab, or use Quick add."
                    )
                } else {
                    EmptyStateView(
                        icon: "leaf",
                        title: "No products",
                        message: "No products match \"\(viewModel.searchText)\"."
                    )
                }
            } else {
                ProductCatalogView(products: products, viewMode: viewMode) { product in
                    add(product)
                }
            }
        }
    }

    private func add(_ product: Product) {
        viewModel.addToCart(product)
        searchFocused = false
        showingCartReview = true
    }

    // MARK: Corner buttons

    /// Both are small round buttons in the corner so the catalogue keeps its
    /// full height — Android's two FloatingActionButtons. Cart sits above Quick
    /// add and only appears once something is on the bill.
    private var cornerButtons: some View {
        VStack(alignment: .trailing, spacing: PlantbillSpacing.sm) {
            if !viewModel.cartLines.isEmpty {
                Button {
                    searchFocused = false
                    showingCartReview = true
                } label: {
                    Image(systemName: "cart.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(PlantbillColor.green)
                        )
                        .overlay(alignment: .topTrailing) {
                            Text("\(viewModel.itemCount)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .frame(minWidth: 22, minHeight: 22)
                                .background(Capsule().fill(PlantbillColor.error))
                                .offset(x: 6, y: -6)
                        }
                        .shadow(color: PlantbillColor.green.opacity(0.35), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Review & pay"))
                .accessibilityValue(Text("\(viewModel.itemCount) items"))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Button {
                searchFocused = false
                showingQuickAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(PlantbillColor.green)
                    .frame(width: 60, height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(PlantbillColor.greenTint)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Quick add item"))
        }
        .padding(PlantbillSpacing.md)
    }

    // MARK: Held bills bar

    @ViewBuilder
    private var heldBillsBar: some View {
        if !viewModel.heldBills.isEmpty {
            VStack(spacing: 0) {
                Divider()
                SecondaryButton(title: "Held bills (\(viewModel.heldBills.count))", systemImage: "pause.fill") {
                    searchFocused = false
                    showingHeldBills = true
                }
                .padding(.horizontal, PlantbillSpacing.md)
                .padding(.vertical, PlantbillSpacing.sm)
            }
            .background(.bar)
        }
    }

    // MARK: Toast

    @ViewBuilder
    private var toastView: some View {
        if let toast = viewModel.toast {
            toast.text
                .font(PlantbillTypography.body)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, PlantbillSpacing.md)
                .padding(.vertical, PlantbillSpacing.sm)
                .background(
                    Capsule().fill(PlantbillColor.textPrimary.opacity(0.92))
                )
                .padding(.horizontal, PlantbillSpacing.md)
                .padding(.top, PlantbillSpacing.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

extension BillToast {
    /// Android's wording for each message, as localizable text.
    var text: Text {
        switch self {
        case .addedToCart(let name): return Text("Added \(name) to cart")
        case .added(let name): return Text("Added \(name)")
        case .billHeld: return Text("Bill held. Open “Held bills” to continue it later.")
        case .voiceNeedsProducts: return Text("Add a few products first, then use voice search.")
        case .voiceUnavailable: return Text("Voice search isn't available on this device.")
        }
    }
}

#Preview {
    BillView()
        .environmentObject(AuthSession())
        .environmentObject(NotificationsStore())
}

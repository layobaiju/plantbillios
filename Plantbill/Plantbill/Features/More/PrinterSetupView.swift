import Combine
import SwiftUI

@MainActor
final class PrinterSetupViewModel: ObservableObject {
    private let manager = BLEPrinterManager()

    /// `state` and `discovered` read through to `manager`, so this view model
    /// has to re-publish the manager's changes as its own -- under the old
    /// `@Observable` these nested reads were tracked automatically, but
    /// `ObservableObject` only publishes what this object itself declares.
    private var managerObservation: AnyCancellable?

    @Published private(set) var connectingId: UUID?
    @Published private(set) var isSendingTest = false
    @Published var message: String?

    var state: PrinterConnectionState { manager.state }
    var discovered: [DiscoveredPrinter] { manager.discoveredPrinters }

    init() {
        managerObservation = manager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func scan() { manager.startScan() }
    func stopScan() { manager.stopScan() }

    func connect(_ printer: DiscoveredPrinter) async {
        connectingId = printer.id
        message = nil
        do {
            try await manager.connect(printer)
            message = "Connected to \(printer.name). Try \"Send test print\" below."
        } catch let error as PrinterTransportError {
            message = error.errorDescription
        } catch {
            message = "Couldn't connect to that device."
        }
        connectingId = nil
    }

    func sendTestPrint(shopName: String) async {
        isSendingTest = true
        message = nil
        do {
            try await manager.write(EscPosTestPrint.bytes(shopName: shopName))
            message = "Sent — check the printer for output."
        } catch let error as PrinterTransportError {
            message = error.errorDescription
        } catch {
            message = "Couldn't send to the printer."
        }
        isSendingTest = false
    }

    func disconnect() {
        manager.disconnect()
    }

    func dismissMessage() { message = nil }
}

struct PrinterSetupView: View {
    let shopName: String

    @StateObject private var viewModel = PrinterSetupViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PlantbillSpacing.lg) {
                explanationCard

                switch viewModel.state {
                case .unsupported:
                    ErrorStateView(message: "This iPhone doesn't support Bluetooth Low Energy.")
                        .frame(height: 200)
                case .unauthorized:
                    ErrorStateView(message: "Plantbill needs Bluetooth access. Turn it on in Settings → Plantbill.")
                        .frame(height: 200)
                case .poweredOff:
                    ErrorStateView(message: "Turn on Bluetooth to look for a printer.")
                        .frame(height: 200)
                default:
                    scanSection
                }

                if let message = viewModel.message {
                    Text(message)
                        .font(PlantbillTypography.body)
                        .foregroundStyle(PlantbillColor.textSecondary)
                }
            }
            .padding(PlantbillSpacing.lg)
        }
        .background(PlantbillColor.background)
        .navigationTitle("Printer")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { viewModel.stopScan() }
    }

    private var explanationCard: some View {
        PlantbillCard {
            VStack(alignment: .leading, spacing: PlantbillSpacing.sm) {
                Text("Bluetooth printer check")
                    .font(PlantbillTypography.bodyEmphasized)
                    .foregroundStyle(PlantbillColor.textPrimary)
                Text("Bills print through AirPrint, which finds Wi-Fi printers on your network automatically. Use this screen to see whether a Bluetooth receipt printer can connect to this iPhone and print a test page. iPhone works only with printers that support Bluetooth Low Energy (BLE).")
                    .font(PlantbillTypography.body)
                    .foregroundStyle(PlantbillColor.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var scanSection: some View {
        switch viewModel.state {
        case .connected, .ready:
            connectedSection
        default:
            VStack(alignment: .leading, spacing: PlantbillSpacing.md) {
                if viewModel.state == .scanning {
                    SecondaryButton(title: "Stop scanning") { viewModel.stopScan() }
                } else {
                    PrimaryButton(title: "Scan for nearby devices") { viewModel.scan() }
                }

                if viewModel.discovered.isEmpty {
                    Text(viewModel.state == .scanning ? "Looking for nearby Bluetooth devices…" : "Turn on your printer, then tap Scan.")
                        .font(PlantbillTypography.body)
                        .foregroundStyle(PlantbillColor.textSecondary)
                } else {
                    ForEach(viewModel.discovered) { device in
                        DeviceRow(
                            device: device,
                            isConnecting: viewModel.connectingId == device.id,
                            onConnect: { Task { await viewModel.connect(device) } }
                        )
                    }
                }
            }
        }
    }

    private var connectedSection: some View {
        VStack(alignment: .leading, spacing: PlantbillSpacing.md) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(PlantbillColor.green)
                Text("Connected")
                    .font(PlantbillTypography.bodyEmphasized)
                    .foregroundStyle(PlantbillColor.textPrimary)
            }
            PrimaryButton(title: "Send test print", isLoading: viewModel.isSendingTest) {
                Task { await viewModel.sendTestPrint(shopName: shopName) }
            }
            SecondaryButton(title: "Disconnect") { viewModel.disconnect() }
        }
    }
}

private struct DeviceRow: View {
    let device: DiscoveredPrinter
    let isConnecting: Bool
    let onConnect: () -> Void

    var body: some View {
        PlantbillCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(PlantbillTypography.bodyEmphasized)
                        .foregroundStyle(PlantbillColor.textPrimary)
                    Text("Signal: \(device.rssi) dBm")
                        .font(PlantbillTypography.caption)
                        .foregroundStyle(PlantbillColor.textSecondary)
                }
                Spacer()
                SecondaryButton(title: "Connect", isLoading: isConnecting, action: onConnect)
                    .frame(width: 120)
            }
        }
    }
}

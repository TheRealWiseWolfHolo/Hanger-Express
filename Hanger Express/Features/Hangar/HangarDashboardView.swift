import SwiftUI

struct HangarDashboardView: View {
    enum PackageFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case giftable = "Giftable"
        case reclaimable = "Reclaimable"
        case upgradeable = "Upgradeable"

        var id: Self { self }
    }

    let appModel: AppModel
    let snapshot: HangarSnapshot

    @State private var filter: PackageFilter = .all
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MetricCard(
                        title: "Packages",
                        primaryValue: "\(snapshot.metrics.packageCount)",
                        secondaryValue: "Ships \(snapshot.metrics.shipCount)"
                    )

                    MetricCard(
                        title: "Value",
                        primaryValue: snapshot.metrics.totalOriginalValue.usdString,
                        secondaryValue: "Current \(snapshot.metrics.totalCurrentValue.usdString)"
                    )

                    MetricCard(
                        title: "Actions",
                        primaryValue: "Giftable \(snapshot.metrics.giftableCount)",
                        secondaryValue: "Reclaimable \(snapshot.metrics.reclaimableCount)"
                    )
                } header: {
                    Text("Snapshot")
                }

                Section {
                    Picker("Filter", selection: $filter) {
                        ForEach(PackageFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    ForEach(filteredPackages) { package in
                        NavigationLink {
                            HangarPackageDetailView(package: package)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                RemoteThumbnailView(
                                    url: package.thumbnailURL,
                                    fallbackSystemImage: "shippingbox.fill",
                                    size: 72
                                )

                                VStack(alignment: .leading, spacing: 8) {
                                    Text(package.title)
                                        .font(.headline)
                                    Text("\(package.status) • \(package.insurance)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    HStack {
                                        Text(package.originalValueUSD.usdString)
                                        Text(package.canGift ? "Giftable" : "Locked")
                                        Text(package.canReclaim ? "Reclaimable" : "No Melt")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Pledges")
                } footer: {
                    Text("This screen should stay read-only in v1, even after live RSI sync is enabled.")
                }
            }
            .searchable(text: $searchText, prompt: "Search packages, ships, insurance")
            .navigationTitle("Hangar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(appModel.isRefreshing ? "Refreshing..." : "Refresh") {
                        Task {
                            await appModel.refresh()
                        }
                    }
                    .disabled(appModel.isRefreshing)
                }
            }
        }
    }

    private var filteredPackages: [HangarPackage] {
        snapshot.packages.filter { package in
            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case .giftable:
                matchesFilter = package.canGift
            case .reclaimable:
                matchesFilter = package.canReclaim
            case .upgradeable:
                matchesFilter = package.canUpgrade
            }

            guard matchesFilter else {
                return false
            }

            guard !searchText.isEmpty else {
                return true
            }

            let haystack = [
                package.title,
                package.status,
                package.insurance,
                package.contents.map(\.title).joined(separator: " ")
            ].joined(separator: " ").localizedLowercase

            return haystack.contains(searchText.localizedLowercase)
        }
    }
}

private struct HangarPackageDetailView: View {
    let package: HangarPackage

    var body: some View {
        List {
            if let thumbnailURL = package.thumbnailURL {
                Section {
                    RemoteThumbnailView(
                        url: thumbnailURL,
                        fallbackSystemImage: "shippingbox.fill",
                        size: 180
                    )
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                }
            }

            Section {
                LabeledContent("Status", value: package.status)
                LabeledContent("Insurance", value: package.insurance)
                LabeledContent("Acquired", value: package.acquiredAt.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Original Value", value: package.originalValueUSD.usdString)
                LabeledContent("Current Value", value: package.currentValueUSD.usdString)
            } header: {
                Text("Package")
            }

            Section {
                ForEach(package.contents) { item in
                    PackageItemRow(item: item)
                }
            } header: {
                Text("Contents")
            }
        }
        .navigationTitle(package.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PackageItemRow: View {
    let item: PackageItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteThumbnailView(
                url: item.imageURL,
                fallbackSystemImage: fallbackSystemImage,
                size: 72
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.headline)

                Text("\(item.category.rawValue) • \(item.detail)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let pricing = item.upgradePricing {
                    UpgradePricingSummary(pricing: pricing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    private var fallbackSystemImage: String {
        switch item.category {
        case .ship:
            return "airplane"
        case .vehicle:
            return "car.fill"
        case .gamePackage:
            return "shippingbox.fill"
        case .flair:
            return "sparkles"
        case .upgrade:
            return "arrow.up.right.square"
        case .perk:
            return "gift.fill"
        }
    }
}

private struct UpgradePricingSummary: View {
    let pricing: PackageItem.UpgradePricing

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledValueRow(label: "Melt Value", value: pricing.meltValueUSD?.usdString ?? "Not separable from this package")
            LabeledValueRow(label: "Actual Value", value: pricing.actualValueUSD?.usdString ?? "Unavailable")
            LabeledValueRow(
                label: "From",
                value: "\(pricing.sourceShipName) • MSRP \(pricing.sourceShipMSRPUSD?.usdString ?? "Unavailable")"
            )
            LabeledValueRow(
                label: "To",
                value: "\(pricing.targetShipName) • MSRP \(pricing.targetShipMSRPUSD?.usdString ?? "Unavailable")"
            )
        }
        .padding(.top, 4)
    }
}

private struct LabeledValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }
}

private struct RemoteThumbnailView: View {
    let url: URL?
    let fallbackSystemImage: String
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallback
                    case .empty:
                        ProgressView()
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var fallback: some View {
        Image(systemName: fallbackSystemImage)
            .font(.title2)
            .foregroundStyle(.secondary)
    }
}

private struct MetricCard: View {
    let title: String
    let primaryValue: String
    let secondaryValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(primaryValue)
                .font(.headline)
                .monospacedDigit()
            Text(secondaryValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

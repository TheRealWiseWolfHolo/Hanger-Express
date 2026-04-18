import SwiftUI

struct FleetView: View {
    let snapshot: HangarSnapshot

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedShips, id: \.manufacturer) { group in
                    Section(group.manufacturer) {
                        ForEach(group.ships) { ship in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(ship.displayName)
                                    .font(.headline)
                                Text("\(ship.role) • \(ship.insurance)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("\(ship.sourcePackageName) • \(ship.meltValueUSD.usdString)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Fleet")
        }
    }

    private var groupedShips: [(manufacturer: String, ships: [FleetShip])] {
        Dictionary(grouping: snapshot.fleet, by: \.manufacturer)
            .map { key, value in
                (manufacturer: key, ships: value.sorted { $0.displayName < $1.displayName })
            }
            .sorted { $0.manufacturer < $1.manufacturer }
    }
}

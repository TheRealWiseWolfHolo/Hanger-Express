import SwiftUI

struct BuybackView: View {
    let snapshot: HangarSnapshot

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(snapshot.buyback) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.headline)
                            Text("Recovered value \(item.recoveredValueUSD.usdString)")
                                .font(.subheadline)
                            Text("\(item.addedToBuybackAt.formatted(date: .abbreviated, time: .omitted)) • \(item.notes)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text("Buy-back planning belongs in the organizer. Executing buy-backs should stay out of the app until the account risk is fully understood.")
                }
            }
            .navigationTitle("Buy Back")
        }
    }
}

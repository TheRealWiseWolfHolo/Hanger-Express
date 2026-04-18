import SwiftUI

struct DashboardTabView: View {
    let appModel: AppModel
    let snapshot: HangarSnapshot

    var body: some View {
        TabView(selection: selection) {
            HangarDashboardView(appModel: appModel, snapshot: snapshot)
                .tabItem {
                    Label("Hangar", systemImage: "shippingbox")
                }
                .tag(AppModel.Tab.hangar)

            FleetView(snapshot: snapshot)
                .tabItem {
                    Label("Fleet", systemImage: "airplane")
                }
                .tag(AppModel.Tab.fleet)

            BuybackView(snapshot: snapshot)
                .tabItem {
                    Label("Buy Back", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }
                .tag(AppModel.Tab.buyback)

            SettingsView(appModel: appModel, snapshot: snapshot)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppModel.Tab.settings)
        }
        .safeAreaInset(edge: .top) {
            if let progress = appModel.refreshProgress {
                RefreshProgressCard(progress: progress, compact: true)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: appModel.refreshProgress)
    }

    private var selection: Binding<AppModel.Tab> {
        Binding(
            get: { appModel.selectedTab },
            set: { appModel.selectedTab = $0 }
        )
    }
}

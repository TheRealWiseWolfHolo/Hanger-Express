import SwiftUI

@main
struct Hanger_ExpressApp: App {
    @State private var appModel: AppModel

    init() {
        _appModel = State(initialValue: AppModel(environment: .live))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appModel: appModel)
        }
    }
}

import SwiftUI

struct ContentView: View {
    let appModel: AppModel

    var body: some View {
        RootView(appModel: appModel)
    }
}

#Preview {
    ContentView(appModel: AppModel(environment: .preview))
}

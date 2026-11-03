import SwiftUI

struct RootView: View {
    @ObservedObject var td = TDService.shared

    var body: some View {
        switch td.authState {
        case .ready:
            MainView()
        default:
            SetupView()
        }
    }
}

import SwiftUI

struct MainView: View {
    var body: some View {
        TabView {
            SummaryView()
                .tabItem { Label("总结", systemImage: "sparkles") }
            GroupsView()
                .tabItem { Label("群组", systemImage: "person.3") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}

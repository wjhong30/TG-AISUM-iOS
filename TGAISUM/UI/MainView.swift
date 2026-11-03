import SwiftUI

struct MainView: View {
    var body: some View {
        TabView {
            ChatListView()
                .tabItem { Label("消息", systemImage: "bubble.left.and.bubble.right") }
            GroupsView()
                .tabItem { Label("群组", systemImage: "person.3") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}

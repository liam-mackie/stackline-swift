import SwiftUI

struct ContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            MainStatusView(coordinator: coordinator)
                .tabItem {
                    Image(systemName: "info.circle")
                    Text("Status")
                }
                .tag(0)
            
            StackDetailsView(coordinator: coordinator)
                .tabItem {
                    Image(systemName: "rectangle.stack")
                    Text("Stacks")
                }
                .tag(1)
            
            ConfigurationView(configManager: coordinator.configManager)
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .tag(2)
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}
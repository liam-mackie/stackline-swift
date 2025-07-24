import SwiftUI

struct MainStatusView: View {
    @ObservedObject var coordinator: AppCoordinator
    
    var body: some View {
        VStack(spacing: 20) {
            HeaderView()
            
            StatusView(coordinator: coordinator)
            
            ControlsView(coordinator: coordinator)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
}
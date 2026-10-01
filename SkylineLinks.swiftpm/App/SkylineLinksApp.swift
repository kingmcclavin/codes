import SwiftUI

@main
struct SkylineLinksApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

enum AppScreen: Equatable {
    case menu
    case courses
    case clubs
    case packs
    case settings
    case playing(courseIndex: Int, length: RoundLength)
}

struct RootView: View {
    @StateObject private var store = GameStore()
    @State private var screen: AppScreen = .menu

    var body: some View {
        ZStack {
            switch screen {
            case .menu:
                MainMenuView(store: store, navigate: go)
                    .transition(.opacity)
            case .courses:
                CourseSelectView(store: store, navigate: go)
                    .transition(.move(edge: .trailing))
            case .clubs:
                ClubCollectionView(store: store, navigate: go)
                    .transition(.move(edge: .trailing))
            case .packs:
                PackShopView(store: store, navigate: go)
                    .transition(.move(edge: .trailing))
            case .settings:
                SettingsView(store: store, navigate: go)
                    .transition(.move(edge: .trailing))
            case let .playing(courseIndex, length):
                GameView(store: store, courseIndex: courseIndex, length: length, navigate: go)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: screen)
    }

    private func go(_ s: AppScreen) {
        screen = s
    }
}

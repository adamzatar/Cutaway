//
//  CutawayApp.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import SwiftUI

@main
struct CutawayApp: App {
    // Persisted flags
    @AppStorage("hasSeenIntro") private var hasSeenIntro: Bool = false
    @AppStorage("shouldAutoOpenPickerOnce") private var shouldAutoOpenPickerOnce = false

    var body: some Scene {
        WindowGroup {
            RootHost(
                hasSeenIntro: $hasSeenIntro
            )
            .preferredColorScheme(.dark) // optional
        }
    }
}

/// Hosts Home, Intro (when needed), and the animated Splash overlay.
private struct RootHost: View {
    @Binding var hasSeenIntro: Bool

    @State private var showSplash = true
    @State private var presentIntro = false

    var body: some View {
        ZStack {
            // Your real app content
            HomeView()
                .environmentObject(LibraryStore())
                .onAppear {
                    if !hasSeenIntro { presentIntro = true }
                }
                .fullScreenCover(isPresented: $presentIntro) {
                    IntroView(
                        hasSeenIntro: Binding(
                            get: { hasSeenIntro },
                            set: { newVal in
                                hasSeenIntro = newVal
                                if newVal == true {
                                    UserDefaults.standard.set(true, forKey: "shouldAutoOpenPickerOnce")
                                }
                            }
                        ),
                        startNewEpisode: {
                            hasSeenIntro = true
                            UserDefaults.standard.set(true, forKey: "shouldAutoOpenPickerOnce")
                            presentIntro = false
                        }
                    )
                    .interactiveDismissDisabled(true) // force a choice on first run
                }

            // Animated splash overlay
            if showSplash {
                SplashView {
                    withAnimation(.easeInOut(duration: 0.25)) { showSplash = false }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .onAppear {
            // failsafe: hide splash if animations are skipped
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if showSplash { withAnimation { showSplash = false } }
            }
        }
    }
}

extension Notification.Name {
    static let CutawayOpenPicker = Notification.Name("CutawayOpenPicker")
    static let CutawayNewReaction = Notification.Name("CutawayNewReaction")
}

//
//  CutawayApp.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

//
//  CutawayApp.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/15/25.
//

import SwiftUI

@main
struct CutawayApp: App {
    @StateObject private var library = LibraryStore()
    @AppStorage("hasSeenIntro") private var hasSeenIntro: Bool = false
    @State private var showHomePicker: Bool = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasSeenIntro {
                    HomeView()
                        .environmentObject(library)
                        .onChange(of: showHomePicker) { _, newValue in
                            // no-op, just here to keep reference if needed
                        }
                        .onAppear {
                            // If intro requested immediate import, toggle flag the HomeView can bind to
                            if showHomePicker {
                                // Post a tiny delay so HomeView is in the tree before we flip its state.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    NotificationCenter.default.post(name: .CutawayOpenPicker, object: nil)
                                    showHomePicker = false
                                }
                            }
                        }
                } else {
                    IntroView(hasSeenIntro: $hasSeenIntro) { // Start New Episode
                        showHomePicker = true
                    }
                    .environmentObject(library)
                }
            }
        }
    }
}

// A lightweight way to tell HomeView to open the picker right away.
extension Notification.Name {
    static let CutawayOpenPicker = Notification.Name("CutawayOpenPicker")
}

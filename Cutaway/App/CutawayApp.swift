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
    @AppStorage("shouldAutoOpenPickerOnce") private var shouldAutoOpenPickerOnce: Bool = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasSeenIntro {
                    TabRoot()
                        .environmentObject(library)
                        .onAppear {
                            // If Intro requested immediate import, tell Home to open the picker.
                            if shouldAutoOpenPickerOnce {
                                shouldAutoOpenPickerOnce = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                    NotificationCenter.default.post(name: .CutawayOpenPicker, object: nil)
                                }
                            }
                        }
                } else {
                    IntroView(hasSeenIntro: $hasSeenIntro) {
                        // “Start New Episode” pressed on Intro:
                        shouldAutoOpenPickerOnce = true
                    }
                    .environmentObject(library)
                }
            }
        }
    }
}

extension Notification.Name {
    static let CutawayOpenPicker = Notification.Name("CutawayOpenPicker")
    static let CutawayNewReaction = Notification.Name("CutawayNewReaction")
}

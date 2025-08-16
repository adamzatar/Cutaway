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
import Foundation

@main
struct CutawayApp: App {
    @StateObject private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(library)
        }
    }
}

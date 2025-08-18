//
//  TabRoot.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/17/25.
//


import SwiftUI

enum MainTab: Hashable {
    case home, record, library, settings
}

struct TabRoot: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var selection: MainTab = .home

    var body: some View {
        TabView(selection: $selection) {

            // HOME
            NavigationStack {
                HomeView()
                    .navigationTitle("")
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            .tag(MainTab.home)

            // RECORD
            NavigationStack {
                RecordTabView()
                    .navigationTitle("Record")
            }
            .tabItem {
                Label("Record", systemImage: "camera.fill")
            }
            .tag(MainTab.record)

            // LIBRARY
            NavigationStack {
                LibraryView()
                    .navigationTitle("Library")
            }
            .tabItem {
                Label("Library", systemImage: "sparkles.tv")
            }
            .tag(MainTab.library)

            // SETTINGS
            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(MainTab.settings)
        }
        .environmentObject(library) // pass the store to all tabs
    }
}

/// A dedicated tab that opens the camera and posts a notification when a clip is recorded.
/// HomeView listens and adds the reaction.
struct RecordTabView: View {
    @State private var showingRecorder = true  // auto-present when entering the tab
    var body: some View {
        VStack(spacing: 16) {
            Text("Record a reaction with the front camera.")
                .foregroundStyle(.secondary)

            Button {
                showingRecorder = true
            } label: {
                Label("Open Recorder", systemImage: "camera.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $showingRecorder) {
            ReactionRecordView { url in
                // Broadcast the new reaction to whoever cares (HomeView).
                NotificationCenter.default.post(name: .CutawayNewReaction, object: url)
            }
        }
    }
}

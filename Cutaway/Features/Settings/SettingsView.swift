//
//  SettingsView.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/17/25.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @AppStorage("hasSeenIntro") private var hasSeenIntro = true
    @AppStorage("forceIntroNextLaunch") private var forceIntroNextLaunch = false
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Onboarding")) {
                    Toggle("Show Intro Next Launch", isOn: $forceIntroNextLaunch)
                        .tint(.accentColor)

                    Button {
                        hasSeenIntro = false
                    } label: {
                        Label("Reset Onboarding Now", systemImage: "arrow.counterclockwise")
                    }
                }

                Section(header: Text("Library")) {
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Label("Clear All Series & Episodes", systemImage: "trash")
                    }
                }

                Section {
                    Text("Cutaway v0.2 (MVP+)")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete all episodes and series?",
                                isPresented: $confirmClear,
                                titleVisibility: .visible) {
                Button("Delete Everything", role: .destructive) {
                    library.clearAllSeries()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

#Preview {
    SettingsView().environmentObject(LibraryStore())
}

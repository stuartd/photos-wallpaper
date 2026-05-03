//
//  ContentView.swift
//  photos-wallpaper
//
//  Created by Stuart on 28/04/2026.
//

import SwiftUI

struct ContentView: View {
    /// Builds the placeholder content view shown in previews; it is currently separate from the menu bar app flow.
    var body: some View {
        // Stack the placeholder icon and label vertically.
        VStack {
            // Show a globe symbol as the preview's placeholder image.
            Image(systemName: "globe")
                // Increase the symbol size to make it more visible in the preview.
                .imageScale(.large)
                // Apply the accent tint style to the symbol.
                .foregroundStyle(.tint)
            // Show placeholder text beneath the symbol.
            Text("Hello, world!")
        }
        // Add padding around the stack so the preview content is not cramped.
        .padding()
    }
}

#Preview {
    ContentView()
}

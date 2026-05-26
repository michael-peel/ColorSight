//
//  ColorSightApp.swift
//  ColorSight
//
//  Created by Michael Peel on 5/21/26.
//

import SwiftUI
import SwiftData

@main
struct ColorSightApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: ColorSwatch.self)
    }
}

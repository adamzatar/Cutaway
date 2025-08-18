//
//  Color+Hex.swift
//  Cutaway
//
//  Created by Adam Zaatar on 8/17/25.
//

import Foundation
import SwiftUI

// Extensions/Color+Hex.swift
public extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self = Color(
            .sRGB,
            red:   Double((hex >> 16) & 0xff)/255,
            green: Double((hex >>  8) & 0xff)/255,
            blue:  Double( hex        & 0xff)/255,
            opacity: alpha
        )
    }
}

import SwiftUI
import Foundation
import os

// MARK: - Logging

private let logger = Logger(subsystem: "sh.mackie.stackline", category: "codable-color")

// MARK: - Codable Color Support

struct CodableColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
    
    init(_ color: Color) {
        let nsColor = NSColor(color)
        
        let resolvedColor: NSColor
        if #available(macOS 10.15, *) {
            resolvedColor = nsColor.usingColorSpace(.sRGB) ?? NSColor.black
        } else {
            resolvedColor = nsColor
        }
        
        if let ciColor = CIColor(color: resolvedColor) {
            self.red = Double(ciColor.red)
            self.green = Double(ciColor.green)
            self.blue = Double(ciColor.blue)
            self.alpha = Double(ciColor.alpha)
        } else {
            logger.warning("Could not convert color to CIColor, using default black")
            self.red = 0.0
            self.green = 0.0
            self.blue = 0.0
            self.alpha = 1.0
        }
    }
    
    var color: Color {
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
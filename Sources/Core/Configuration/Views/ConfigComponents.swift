import SwiftUI

// MARK: - Helper Components

struct ConfigSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            content
        }
    }
}

struct ConfigSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let formatter: ((Double) -> Int)?
    let onEditingChanged: (Double) -> Void
    
    init(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String,
        formatter: ((Double) -> Int)? = nil,
        onEditingChanged: @escaping (Double) -> Void
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.formatter = formatter
        self.onEditingChanged = onEditingChanged
    }
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
            
            Spacer()
            
            Slider(value: $value, in: range, step: step) { editing in
                if !editing {
                    onEditingChanged(value)
                }
            }
            
            Text(formattedValue)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
    }
    
    private var formattedValue: String {
        if let formatter = formatter {
            return "\(formatter(value))\(unit)"
        } else {
            if abs(value - value.rounded()) < 0.01 {
                return "\(Int(value.rounded()))\(unit)"
            } else {
                return String(format: "%.1f\(unit)", value)
            }
        }
    }
}

struct ConfigColorPicker: View {
    let title: String
    @Binding var color: Color
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
            
            Spacer()
            
            ColorPicker("", selection: $color)
                .labelsHidden()
                .frame(width: 40, height: 30)
        }
    }
}
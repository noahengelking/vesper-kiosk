import SwiftUI

struct VesperPalette {
    let background: Color
    let panel: Color
    let foreground: Color
    let dim: Color
    let line: Color
    let accent: Color
    let button: Color
    let buttonStrong: Color
    let isDark: Bool

    static let dark = VesperPalette(
        background: Color(hex: 0x0B0B0C),
        panel: Color(hex: 0x0D0D0F),
        foreground: Color(hex: 0xE8E6E1),
        dim: Color(hex: 0x7D7B76),
        line: Color(hex: 0x26262A),
        accent: Color(hex: 0xF2B84B),
        button: Color(hex: 0x232326),
        buttonStrong: Color(hex: 0x333338),
        isDark: true
    )

    static let light = VesperPalette(
        background: Color(hex: 0xF3F0E8),
        panel: Color(hex: 0xEDE9DF),
        foreground: Color(hex: 0x1C1C1E),
        dim: Color(hex: 0x85817A),
        line: Color(hex: 0xDCD7CA),
        accent: Color(hex: 0xC98D12),
        button: Color(hex: 0xE2DDD0),
        buttonStrong: Color(hex: 0xD2CCBC),
        isDark: false
    )
}

private struct VesperPaletteKey: EnvironmentKey {
    static let defaultValue = VesperPalette.dark
}

extension EnvironmentValues {
    var vesperPalette: VesperPalette {
        get { self[VesperPaletteKey.self] }
        set { self[VesperPaletteKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: opacity
        )
    }

}

extension Font {
    static func vesperLabel(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }

    static func vesperTitle(_ size: CGFloat) -> Font {
        .system(size: size, weight: .light, design: .rounded)
    }
}

extension View {
    func vesperLabel(size: CGFloat = 11) -> some View {
        self.font(.vesperLabel(size))
            .tracking(2.4)
            .textCase(.uppercase)
    }
}

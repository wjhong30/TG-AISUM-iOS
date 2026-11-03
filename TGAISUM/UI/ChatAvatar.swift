import SwiftUI

/// 从名字派生稳定颜色的圆角头像（取首字）
struct ChatAvatar: View {
    let name: String
    var size: CGFloat = 40

    private var initials: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return "?" }
        return String(first)
    }

    private var gradient: LinearGradient {
        let seed = abs(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
        let h1 = Double(seed % 360) / 360
        let h2 = Double((seed * 7 + 40) % 360) / 360
        return LinearGradient(
            colors: [Color(hue: h1, saturation: 0.55, brightness: 0.85),
                     Color(hue: h2, saturation: 0.6, brightness: 0.7)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24)
                .fill(gradient)
            Text(initials)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

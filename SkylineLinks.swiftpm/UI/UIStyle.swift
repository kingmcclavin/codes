import SwiftUI

/// Shared colours and small reusable views.
enum UIStyle {
    static let background = LinearGradient(
        colors: [Color(red: 0.06, green: 0.16, blue: 0.12), Color(red: 0.02, green: 0.07, blue: 0.08)],
        startPoint: .top, endPoint: .bottom)
    static let panel = Color.white.opacity(0.07)
    static let panelStroke = Color.white.opacity(0.12)
    static let accent = Color(red: 0.45, green: 0.86, blue: 0.42)
    static let gold = Color(red: 1.0, green: 0.78, blue: 0.25)
    static let danger = Color(red: 0.95, green: 0.35, blue: 0.35)
}

struct CoinLabel: View {
    let amount: Int
    var font: Font = .headline

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(UIStyle.gold)
                .frame(width: 18, height: 18)
                .overlay(Text("C").font(.system(size: 11, weight: .black)).foregroundColor(.brown))
            Text("\(amount)")
                .font(font.monospacedDigit())
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
    }
}

struct BigButtonStyle: ButtonStyle {
    var color: Color = UIStyle.accent
    var foreground: Color = .black

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .heavy, design: .rounded))
            .foregroundColor(foreground)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(color)
                    .shadow(color: color.opacity(0.4), radius: configuration.isPressed ? 2 : 8, y: configuration.isPressed ? 1 : 4)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(UIStyle.panel)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(UIStyle.panelStroke, lineWidth: 1))
            )
    }
}

extension View {
    func panel() -> some View { modifier(PanelBackground()) }
}

/// Top bar used by menu sub-screens.
struct ScreenHeader: View {
    let title: String
    let coins: Int
    let back: () -> Void

    var body: some View {
        HStack {
            Button(action: back) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Menu")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.white.opacity(0.1)))
            }
            Spacer()
            Text(title)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Spacer()
            CoinLabel(amount: coins)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

struct StatBar: View {
    let label: String
    let value: Double
    var color: Color = UIStyle.accent
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(compact ? .caption2.weight(.bold) : .caption.weight(.bold))
                .foregroundColor(.white.opacity(0.75))
                .frame(width: compact ? 62 : 86, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(color).frame(width: geo.size.width * CGFloat(min(1, max(0, value / 100))))
                }
            }
            .frame(height: compact ? 6 : 8)
            Text("\(Int(value.rounded()))")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundColor(.white)
                .frame(width: 28, alignment: .trailing)
        }
    }
}

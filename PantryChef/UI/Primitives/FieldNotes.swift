import SwiftUI

/// The Field Notes print furniture (spec §10): the page is organized by rules and
/// type, never by floating cards. These are the only structural marks the world
/// uses — dashed hand-rules between sections, solid rules around fact bands,
/// dotted leaders inside ledger rows, squared tags and blocks, and the ❧ tailpiece
/// that ends every page with one true line.

/// A hand-ruled dashed separator.
struct DashedRule: View {
    var opacity: Double = 1

    var body: some View {
        Line()
            .stroke(Theme.Palette.ink.opacity(0.35 * opacity),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(height: 1)
    }
}

/// A solid printed rule (fact bands, the page floor).
struct SolidRule: View {
    var body: some View {
        Rectangle().fill(Theme.Palette.ink.opacity(0.3)).frame(height: 1)
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return p
    }
}

/// Small-caps section label. Tomato tone = act or hurry; quiet = everything else;
/// gold = wins.
struct Eyebrow: View {
    enum Tone { case quiet, urgent, win }
    let text: String
    var tone: Tone = .quiet

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Typography.eyebrow)
            .tracking(Theme.Metric.eyebrowTracking)
            .foregroundStyle(color)
    }

    private var color: Color {
        switch tone {
        case .quiet: return Theme.Palette.ink.opacity(0.6)
        case .urgent: return Theme.Palette.paprika
        case .win: return Theme.Palette.sage
        }
    }
}

/// A ledger row: leading content, a dotted leader, trailing values — the menu/
/// index line of the printed page.
struct LeaderRow<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            leading.layoutPriority(1)   // names keep their words; the leader gives
            Leader()
            trailing.layoutPriority(1)
        }
    }
}

/// The dotted leader between a ledger row's name and its value.
struct Leader: View {
    var body: some View {
        Line()
            .stroke(Theme.Palette.ink.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] - 3 }
    }
}

/// A squared, bordered small-caps tag — "IN", "LOW — LISTED", "WED".
struct OutlineTag: View {
    let text: String
    var tone: Eyebrow.Tone = .quiet
    var dashed = false

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9))
            .tracking(1.6)
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .overlay(
                Rectangle().strokeBorder(
                    color.opacity(tone == .quiet ? 0.6 : 1),
                    style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 2] : []))
            )
    }

    private var color: Color {
        switch tone {
        case .quiet: return Theme.Palette.ink.opacity(0.75)
        case .urgent: return Theme.Palette.paprika
        case .win: return Theme.Palette.sage
        }
    }
}

/// The world's one filled action: a squared tomato block with tracked caps.
struct BlockButton: View {
    let title: String
    var fullWidth = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .medium))
                .tracking(2.4)
                .foregroundStyle(Theme.Palette.cream)
                .padding(.horizontal, 22).padding(.vertical, 10)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .background(Rectangle().fill(Theme.Palette.paprika))
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }
}

/// A bordered, unfilled companion action.
struct OutlineButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.system(size: 11))
                .tracking(2)
                .foregroundStyle(Theme.Palette.ink)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .overlay(Rectangle().strokeBorder(Theme.Palette.ink.opacity(0.4), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }
}

/// The page's closing line: ❧ one true thing ❧
struct Tailpiece: View {
    let text: String

    var body: some View {
        Text("❧\u{2002}\(text)\u{2002}❧")
            .font(Theme.Typography.fact(10))
            .foregroundStyle(Theme.Palette.ink.opacity(0.45))
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }
}

#Preview("Furniture") {
    VStack(alignment: .leading, spacing: 14) {
        Eyebrow(text: "Tonight", tone: .urgent)
        DashedRule()
        LeaderRow {
            Text("🥬 Baby spinach — 300g").font(Theme.Typography.fact(12))
                .foregroundStyle(Theme.Palette.ink)
        } trailing: {
            Text("51 hrs").font(Theme.Typography.fact(12)).foregroundStyle(Theme.Palette.paprika)
        }
        HStack { OutlineTag(text: "In"); OutlineTag(text: "Low — listed", tone: .urgent); OutlineTag(text: "?", dashed: true) }
        HStack { BlockButton(title: "Cook") {}; OutlineButton(title: "⟨ Frittata · Salmon ⟩") {} }
        SolidRule()
        Tailpiece(text: "№ 163 · 3 ready tonight")
    }
    .padding(20)
    .background(Theme.Palette.cream)
}

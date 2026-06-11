import SwiftUI

/// The marker a timeline row shows on the spine (spec §4 "the spine is a ruler").
enum SpineNode: Equatable {
    case now         // paprika node — the present
    case meal        // committed event — hollow ring
    case journal     // a past entry — faded dot
    case expiry      // a deadline — ochre diamond
    case proposal    // a dashed invitation
    case day         // a bare day — minor notch
    case fold        // a compressed quiet run — tick cluster
    case week        // a week boundary — major tick
}

/// The left gutter of a timeline row: the continuous spine line plus this row's
/// marker, sized to the shared ruler width so every row aligns.
struct SpineGutter: View {
    let node: SpineNode
    private let centerX: CGFloat = 13
    private let markerTop: CGFloat = 7

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Theme.Palette.hairline)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .offset(x: centerX - 1)
            marker.offset(x: centerX, y: markerTop)
                .alignmentGuide(.leading) { $0[.leading] }
        }
        .frame(width: Theme.Metric.spineWidth, alignment: .topLeading)
    }

    @ViewBuilder private var marker: some View {
        switch node {
        case .now:
            Circle().fill(Theme.Palette.paprika).frame(width: 14, height: 14)
                .background(Circle().fill(Theme.Palette.paprika.opacity(0.18)).frame(width: 22, height: 22))
                .offset(x: -7, y: 0)
        case .meal:
            Circle().fill(Theme.Palette.cream)
                .overlay(Circle().strokeBorder(Theme.Palette.warmGraySoft, lineWidth: 2))
                .frame(width: 10, height: 10).offset(x: -5, y: 2)
        case .journal:
            Circle().fill(Theme.Palette.warmGraySoft.opacity(0.7)).frame(width: 10, height: 10).offset(x: -5, y: 2)
        case .expiry:
            Rectangle().fill(Theme.Palette.ochre).frame(width: 8, height: 8)
                .rotationEffect(.degrees(45)).offset(x: -4, y: 2)
        case .proposal:
            Circle().strokeBorder(Theme.Palette.paprika.opacity(0.7),
                                  style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                .frame(width: 10, height: 10).offset(x: -5, y: 2)
        case .day:
            Capsule().fill(Theme.Palette.hairline).frame(width: 10, height: 1.5).offset(x: -4, y: 5)
        case .fold:
            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule().fill(Theme.Palette.hairline).frame(width: 8, height: 1.5)
                }
            }
            .offset(x: -3, y: 1)
        case .week:
            Capsule().fill(Theme.Palette.warmGraySoft.opacity(0.5)).frame(width: 16, height: 2).offset(x: -1, y: 5)
        }
    }
}

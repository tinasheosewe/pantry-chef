import SwiftUI

/// Disambiguation: when an ingredient phrase isn't a confident match, the user
/// picks from the ranked catalog candidates — or chooses Custom to define a new
/// one. Never a silent wrong guess (spec §7, the "nonsense → egg" fix).
struct IngredientPicker: View {
    let phrase: String
    let candidates: [IntakeCandidate]
    var onPick: (IntakeCandidate) -> Void
    var onCustom: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Which one?").font(Theme.Typography.dish(22)).foregroundStyle(Theme.Palette.ink)
                    Text("Closest matches for “\(phrase)”.")
                        .font(Theme.Typography.note(11.5)).foregroundStyle(Theme.Palette.warmGray)
                }
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.Palette.warmGray).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 18)
            DashedRule().padding(.horizontal, 20).padding(.top, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(candidates) { candidate in
                        Button { onPick(candidate) } label: {
                            HStack(spacing: 11) {
                                PlateView(name: candidate.name,
                                          composition: PlateComposition(categories: [.other], seed: 1), size: 28)
                                Text(candidate.name).font(Theme.Typography.fact(14.5)).foregroundStyle(Theme.Palette.ink)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 11))
                                    .foregroundStyle(Theme.Palette.warmGraySoft)
                            }
                            .padding(.vertical, 9).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        DashedRule(opacity: 0.5)
                    }
                    // Custom — always last, always available.
                    Button(action: onCustom) {
                        HStack(spacing: 11) {
                            Image(systemName: "plus").font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.Palette.paprika).frame(width: 28)
                            Text("New ingredient: “\(phrase)”")
                                .font(Theme.Typography.fact(14.5)).foregroundStyle(Theme.Palette.paprika)
                            Spacer()
                        }
                        .padding(.vertical, 11).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 24)
            }
        }
        .background(KitchenBackground())
    }
}

import SwiftUI
import SpadesEngine

struct HomeView: View {
    @Environment(AppSettings.self) private var settings
    @State private var playing = false
    @State private var showingRules = false
    @State private var floating = false

    var body: some View {
        ZStack {
            FeltBackground()

            VStack(spacing: 28) {
                Spacer()
                hero
                Spacer()
                rulesSummary
                DifficultyPicker()
                    .padding(.horizontal, 32)
                VStack(spacing: 12) {
                    Button("Deal Me In") { playing = true }
                        .buttonStyle(BrassButtonStyle())
                    Button("House Rules") { showingRules = true }
                        .buttonStyle(BrassButtonStyle(prominent: false))
                }
                .padding(.horizontal, 32)
                if settings.gamesPlayed > 0 {
                    Text("Record \(settings.gamesWon)–\(settings.gamesPlayed - settings.gamesWon)")
                        .font(Theme.label(13))
                        .foregroundStyle(Theme.mist)
                }
            }
            .padding(.bottom, 24)
        }
        .fullScreenCover(isPresented: $playing) {
            GameView()
                .environment(settings)
        }
        .sheet(isPresented: $showingRules) {
            RulesView()
                .environment(settings)
        }
    }

    private var hero: some View {
        VStack(spacing: 6) {
            ZStack {
                CardView(card: Card(.ace, .spades), width: 96)
                    .rotationEffect(.degrees(-14))
                    .offset(x: -54, y: floating ? 4 : 10)
                CardBackView(width: 96)
                    .rotationEffect(.degrees(12))
                    .offset(x: 54, y: floating ? 10 : 4)
                CardView(card: Card(.king, .hearts), width: 104)
                    .offset(y: floating ? -6 : 0)
            }
            .frame(height: 190)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { floating = true }
            }

            Text("SPADES")
                .font(Theme.display(54, weight: .black))
                .tracking(10)
                .foregroundStyle(LinearGradient(colors: [Theme.ivory, Theme.brass], startPoint: .top, endPoint: .bottom))
                .padding(.top, 18)
            Text("your table · your rules")
                .font(Theme.display(16, weight: .regular).italic())
                .foregroundStyle(Theme.mist)
        }
    }

    private var rulesSummary: some View {
        FlowLayout(spacing: 8) {
            ForEach(settings.rules.highlights, id: \.self) { item in
                Text(item)
                    .font(Theme.label(12))
                    .foregroundStyle(Theme.brass)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.brass.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(Theme.brass.opacity(0.3), lineWidth: 0.75))
            }
        }
        .padding(.horizontal, 28)
        .onTapGesture { showingRules = true }
    }
}

/// Three-way opponent strength selector styled to match the table.
struct DifficultyPicker: View {
    @Environment(AppSettings.self) private var settings
    @Namespace private var pill

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Difficulty.allCases) { level in
                    let active = settings.difficulty == level
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { settings.difficulty = level }
                    } label: {
                        Text(level.label)
                            .font(Theme.label(14, weight: .bold))
                            .foregroundStyle(active ? Theme.ink : Theme.mist)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background {
                                if active {
                                    Capsule().fill(Theme.brass).matchedGeometryEffect(id: "pill", in: pill)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Capsule().fill(Theme.panel))
            .overlay(Capsule().strokeBorder(Theme.hairline))
            Text(settings.difficulty.blurb)
                .font(Theme.display(13, weight: .regular).italic())
                .foregroundStyle(Theme.mist)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .frame(minHeight: 34, alignment: .top)
        }
        .sensoryFeedback(.selection, trigger: settings.difficulty)
    }
}

/// Wraps children onto multiple centered lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width && !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let isEmpty = rows[rows.count - 1].indices.isEmpty
            rows[rows.count - 1].indices.append(i)
            rows[rows.count - 1].width += isEmpty ? size.width : size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

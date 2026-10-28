import SwiftUI
import SpadesEngine

// MARK: - Bidding

struct BidPanel: View {
    let legal: [Bid]
    let suggestion: Bid?
    let partnerName: String
    let partnerBid: Bid?
    let onBid: (Bid) -> Void

    @State private var pending: Bid?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your bid")
                    .font(Theme.display(22))
                    .foregroundStyle(Theme.ivory)
                Spacer()
                if let partnerBid {
                    Text("\(partnerName) bid \(partnerBid.description)")
                        .font(Theme.label(13))
                        .foregroundStyle(Theme.usTint)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(1...13, id: \.self) { n in
                    bidButton(.tricks(n), title: "\(n)")
                }
                if legal.contains(.nilBid) {
                    bidButton(.nilBid, title: "Nil")
                }
            }

            if let suggestion {
                Text("Table sense says \(suggestion.description)")
                    .font(Theme.display(13, weight: .regular).italic())
                    .foregroundStyle(Theme.mist)
            }

            Button {
                if let pending { onBid(pending) }
            } label: {
                Text(pending.map { $0.isNil ? "Bid Nil" : "Bid \($0.description)" } ?? "Choose a bid")
            }
            .buttonStyle(BrassButtonStyle())
            .disabled(pending == nil)
            .opacity(pending == nil ? 0.5 : 1)
        }
        .padding(18)
        .panel()
        .onAppear { pending = suggestion }
    }

    private func bidButton(_ bid: Bid, title: String) -> some View {
        let enabled = legal.contains(bid)
        let isSelected = pending == bid
        return Button {
            pending = bid
        } label: {
            Text(title)
                .font(Theme.display(title.count > 2 ? 15 : 19, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 42)
                .foregroundStyle(isSelected ? Theme.ink : Theme.ivory)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Theme.brass : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(suggestion == bid ? Theme.brass : Theme.hairline, lineWidth: suggestion == bid ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.25)
        .animation(.spring(response: 0.2), value: isSelected)
    }
}

struct BlindNilPanel: View {
    let deficit: Int
    let value: Int
    let onDecide: (Bool) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Go blind?")
                .font(Theme.display(26))
                .foregroundStyle(Theme.ivory)
            Text("You're down \(deficit). Bid Blind Nil before looking at your cards: take zero tricks for +\(value), or lose \(value).")
                .font(Theme.label(15, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.mist)
            HStack(spacing: 12) {
                Button("Show my cards") { onDecide(false) }
                    .buttonStyle(BrassButtonStyle(prominent: false))
                Button("Go blind") { onDecide(true) }
                    .buttonStyle(BrassButtonStyle())
            }
        }
        .padding(20)
        .panel()
    }
}

// MARK: - Round summary

struct RoundSummaryView: View {
    let result: RoundResult
    let rules: HouseRules
    let names: [Seat: String]
    let isFinal: Bool
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Hand \(result.roundNumber)")
                .font(Theme.display(26))
                .foregroundStyle(Theme.ivory)

            HStack(alignment: .top, spacing: 12) {
                column(.us)
                column(.them)
            }

            Button(isFinal ? "Final Score" : "Next Hand", action: onContinue)
                .buttonStyle(BrassButtonStyle())
        }
        .padding(20)
        .panel()
    }

    private func column(_ team: Team) -> some View {
        let r = result.teams[team]!
        return VStack(alignment: .leading, spacing: 8) {
            Text(team == .us ? "US" : "THEM")
                .font(Theme.label(12, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(Theme.tint(team))

            ForEach(team.seats, id: \.self) { seat in
                let bid = result.bids[seat] ?? .tricks(0)
                row(names[seat] ?? seat.name, "\(result.tricks[seat] ?? 0) / \(bid.description)")
            }
            Divider().overlay(Theme.hairline)

            if r.contract > 0 {
                row(r.madeContract ? "Made \(r.contract)" : "Set (\(r.tricksTowardContract) of \(r.contract))",
                    signed(r.contractPoints), highlight: r.madeContract ? Theme.tint(team) : Theme.crimson)
            }
            ForEach(r.nilOutcomes, id: \.seat) { n in
                row("\(n.blind ? "Blind nil" : "Nil") \(n.made ? "made" : "failed")", signed(n.points),
                    highlight: n.made ? Theme.brass : Theme.crimson)
            }
            if r.bagsTaken > 0 {
                row("Bags", "+\(r.bagsTaken)")
            }
            if r.bagPenaltyCount > 0 {
                row("Bag penalty", "−\(r.bagPenaltyPoints)", highlight: Theme.crimson)
            }
            Divider().overlay(Theme.hairline)
            row("Hand", signed(r.delta), highlight: Theme.ivory)
            HStack {
                Text("Total")
                    .font(Theme.label(13))
                    .foregroundStyle(Theme.mist)
                Spacer()
                Text("\(r.after.points)")
                    .font(Theme.display(24))
                    .foregroundStyle(Theme.ivory)
            }
            if rules.bagsEnabled {
                BagMeter(bags: r.after.bags, limit: rules.bagLimit)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.04)))
    }

    private func row(_ label: String, _ value: String, highlight: Color = Theme.mist) -> some View {
        HStack {
            Text(label)
                .font(Theme.label(13, weight: .regular))
                .foregroundStyle(Theme.mist)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text(value)
                .font(Theme.label(14, weight: .bold))
                .foregroundStyle(highlight)
                .monospacedDigit()
        }
    }

    private func signed(_ n: Int) -> String { n >= 0 ? "+\(n)" : "−\(-n)" }
}

// MARK: - Game over

struct GameOverView: View {
    let winner: Team
    let scores: [Team: TeamScore]
    let onPlayAgain: () -> Void
    let onLeave: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            Text("♠")
                .font(.system(size: 72))
                .foregroundStyle(winner == .us ? Theme.brass : Theme.mist)
                .scaleEffect(appeared ? 1 : 0.3)
                .rotationEffect(.degrees(appeared ? 0 : -30))
            Text(winner == .us ? "You win the table" : "They take it")
                .font(Theme.display(30, weight: .heavy))
                .foregroundStyle(Theme.ivory)
            Text("\(scores[.us]!.points) – \(scores[.them]!.points)")
                .font(Theme.display(22, weight: .medium))
                .foregroundStyle(Theme.mist)
                .monospacedDigit()
            VStack(spacing: 10) {
                Button("Play Again", action: onPlayAgain)
                    .buttonStyle(BrassButtonStyle())
                Button("Leave Table", action: onLeave)
                    .buttonStyle(BrassButtonStyle(prominent: false))
            }
            .padding(.top, 6)
        }
        .padding(28)
        .panel()
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { appeared = true }
        }
    }
}

// MARK: - In-game menu

struct GameMenuView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    let lastTrick: Trick?
    let names: [Seat: String]
    let onNewGame: () -> Void
    let onLeave: () -> Void

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                if let lastTrick {
                    Section("Last trick") {
                        HStack(spacing: 10) {
                            ForEach(lastTrick.plays, id: \.card) { play in
                                VStack(spacing: 4) {
                                    CardView(card: play.card, width: 48)
                                    Text(names[play.seat] ?? play.seat.name)
                                        .font(Theme.label(11))
                                        .foregroundStyle(Theme.mist)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                }
                Section("Table") {
                    Picker("Pace", selection: $settings.pace) {
                        ForEach(Pace.allCases.filter { $0 != .instant }) { Text($0.label).tag($0) }
                    }
                    Toggle("One-tap play", isOn: $settings.oneTapPlay)
                    Toggle("Show bid suggestion", isOn: $settings.showBidSuggestion)
                }
                Section {
                    Button("New game (same rules)") { dismiss(); onNewGame() }
                    Button("Leave table", role: .destructive) { dismiss(); onLeave() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.feltEdge)
            .navigationTitle("Paused")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Resume") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

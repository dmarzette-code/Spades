import SwiftUI
import SpadesEngine

/// Every house rule in one place, with plain-language explanations.
struct RulesView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(HouseRules.presets, id: \.name) { preset in
                                let active = settings.rules == preset.rules
                                Button(preset.name) { withAnimation { settings.rules = preset.rules } }
                                    .font(Theme.label(13, weight: .bold))
                                    .foregroundStyle(active ? Theme.ink : Theme.brass)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(active ? Theme.brass : Theme.brass.opacity(0.12)))
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } header: {
                    Text("Start from a preset")
                }

                Section {
                    Stepper(value: $settings.rules.winningScore, in: 100...1000, step: 50) {
                        LabeledContent("Play to", value: "\(settings.rules.winningScore)")
                    }
                    Toggle("Mercy rule", isOn: $settings.rules.mercyRuleEnabled)
                    if settings.rules.mercyRuleEnabled {
                        Stepper(value: $settings.rules.losingScore, in: -1000 ... -50, step: 50) {
                            LabeledContent("Lose at", value: "\(settings.rules.losingScore)")
                        }
                    }
                } header: {
                    Text("Game")
                } footer: {
                    Text("With the mercy rule, a team that sinks to the losing score loses immediately.")
                }

                Section {
                    Toggle("Nil allowed", isOn: $settings.rules.nilAllowed)
                    if settings.rules.nilAllowed {
                        Stepper(value: $settings.rules.nilValue, in: 50...200, step: 25) {
                            LabeledContent("Nil worth", value: "±\(settings.rules.nilValue)")
                        }
                        Toggle("Blind nil", isOn: $settings.rules.blindNilAllowed)
                        if settings.rules.blindNilAllowed {
                            Stepper(value: $settings.rules.blindNilValue, in: 100...400, step: 50) {
                                LabeledContent("Blind nil worth", value: "±\(settings.rules.blindNilValue)")
                            }
                            Stepper(value: $settings.rules.blindNilMinDeficit, in: 0...300, step: 25) {
                                LabeledContent("Only when down by", value: "\(settings.rules.blindNilMinDeficit)+")
                            }
                        }
                        Toggle("Failed nil tricks help partner", isOn: $settings.rules.nilTricksCountForPartner)
                    }
                } header: {
                    Text("Nil")
                } footer: {
                    Text("Blind nil is declared before you look at your cards.")
                }

                Section {
                    Toggle("Bag penalty", isOn: $settings.rules.bagsEnabled)
                    if settings.rules.bagsEnabled {
                        Stepper(value: $settings.rules.bagLimit, in: 5...15) {
                            LabeledContent("Every", value: "\(settings.rules.bagLimit) bags")
                        }
                        Stepper(value: $settings.rules.bagPenalty, in: 50...200, step: 25) {
                            LabeledContent("Costs", value: "−\(settings.rules.bagPenalty)")
                        }
                    }
                } header: {
                    Text("Bags (overtricks)")
                } footer: {
                    Text("Each trick over your bid scores 1 point and adds a bag.")
                }

                Section {
                    Stepper(value: $settings.rules.minimumTeamBid, in: 0...6) {
                        LabeledContent("Team minimum (board)", value: settings.rules.minimumTeamBid == 0 ? "Off" : "\(settings.rules.minimumTeamBid)")
                    }
                    Toggle("10+ bid scores double", isOn: $settings.rules.doubleForTenPlus)
                } header: {
                    Text("Bidding")
                }

                Section {
                    Toggle("Spades must be broken", isOn: $settings.rules.spadesMustBeBroken)
                    Toggle("Low club leads first", isOn: $settings.rules.lowClubLeads)
                    Toggle("Jokers", isOn: $settings.rules.jokersEnabled)
                    Toggle("Big deuce (2♠ high)", isOn: $settings.rules.bigDeuce)
                } header: {
                    Text("Cards & play")
                } footer: {
                    Text(trumpOrder)
                }

                Section("Pace") {
                    Picker("AI speed", selection: $settings.pace) {
                        ForEach(Pace.allCases.filter { $0 != .instant }) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("One-tap play", isOn: $settings.oneTapPlay)
                    Toggle("Show bid suggestion", isOn: $settings.showBidSuggestion)
                }
            }
            .tint(Theme.brass)
            .scrollContentBackground(.hidden)
            .background(FeltBackground())
            .navigationTitle("House Rules")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { withAnimation { settings.rules = .standard } }
                }
            }
        }
    }

    private var trumpOrder: String {
        var top: [String] = []
        if settings.rules.jokersEnabled { top += ["Big Joker", "Little Joker"] }
        if settings.rules.bigDeuce { top.append("2♠") }
        top += ["A♠", "K♠", "…"]
        var text = "Trump order: " + top.joined(separator: " › ")
        if settings.rules.jokersEnabled { text += ". The 2♣ and 2♥ are removed to make room for the jokers." }
        return text
    }
}

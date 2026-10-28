# Spades

A Spades game for iPhone and iPad that plays by your house rules and looks good doing it.

## What's here

| Path | What it is |
| --- | --- |
| `Sources/SpadesEngine` | Pure-Swift rules engine, scoring, AI, and game controller. No UI, fully unit-tested. |
| `Tests/SpadesEngineTests` | Scoring, rule-enforcement, and simulation tests (hundreds of full AI games per run). |
| `App/Spades` | The SwiftUI app: home screen, table, bidding, round summaries, house-rules editor. |
| `project.yml` | [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec that generates the Xcode project. |

## Run it

Requires Xcode 15 or later (iOS 17 SDK).

```sh
brew install xcodegen   # once
xcodegen                # generates Spades.xcodeproj
open Spades.xcodeproj
```

Pick an iPhone simulator and press Run. Set your team under *Signing & Capabilities* to run on a device.

Engine tests run anywhere Swift does, including Linux:

```sh
swift test
```

## House rules

All of these can be changed on the **House Rules** screen:

- Winning score, plus an optional mercy rule (lose at −200, etc.)
- Nil on/off and its value; **blind nil**, its value, and how far behind you must be to bid it
- Whether a failed nil's tricks count toward the partner's bid
- Bag penalty on/off, the bag limit, and the penalty size
- **The board**: a minimum combined team bid
- 10-for-200: a made team bid of 10+ scores double
- Spades must be broken (or lead them anytime)
- Low club leads the first trick
- **Jokers** (Big and Little Joker on top; 2♣ and 2♥ removed)
- **Big deuce** (2♠ ranks above the A♠)

Presets: Standard, Quick (250), Jokers & Big Deuce, No Mercy.

## Opponents

Pick **Easy**, **Medium**, or **Hard** on the home screen. Your partner always plays at full strength.

| Level | How it plays |
| --- | --- |
| Easy | Doesn't remember played cards, bids loosely, and makes the occasional careless play. |
| Medium | Card-counting heuristic: tracks voids, covers partner's nil, sets yours, ducks bags. |
| Hard | Before every bid and card it imagines many possible deals of the unseen cards, plays each option to the end of the hand, and picks the best average. |

No AI ever sees hidden cards. Every bot works from a `PlayerView` with only its own hand and what's public at the table, and Hard's imagined deals are built from that alone.

Measured on identical, seat-swapped deals: Medium beats Easy in about 88% of games, and Hard beats the best non-simulating bot (a mistake-free Medium) in about 78% (+14 points per hand). Re-run the measurements with:

```sh
SPADES_TUNE=1 SPADES_GAMES=30 swift test -c release -Xswiftc -enable-testing --filter AIStrengthTests
```

## Roadmap ideas

- Card-passing for nil / blind nil variants
- Stats and hand history
- Online play with friends (Game Center)

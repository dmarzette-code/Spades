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

## The AI plays fair

The AI never sees other players' cards. Each bot gets a `PlayerView` with only its own hand and what has been played or bid at the table. It counts cards, tracks who is void in which suit, covers its partner's nil, tries to set opponents' nils, and avoids bags once its bid is made. In simulation the AI makes about 96% of its bids.

## Roadmap ideas

- Tune AI aggressiveness (it bids a bit conservatively right now)
- Card-passing for nil / blind nil variants
- Stats and hand history
- Online play with friends (Game Center)

# claude-usage-mac

Claude Code usage in the macOS menu bar and as a desktop widget — session and
weekly limit percentages, plus token counts and estimated cost.

A native port of [claude-usage-streamdeck-plugin](https://github.com/saeedkolivand/claude-usage-streamdeck-plugin)
for people who don't own a Stream Deck.

> **Status: built, not yet run on real hardware.** Everything compiles, 43 tests
> pass, and the UI is reviewed through rendered snapshots — but the project is
> developed on Windows, so nobody has launched it on a Mac yet. See
> [Unverified](#unverified) before trusting it.

## Install

Requires macOS 14 or later.

```sh
brew install xcodegen
./build.sh
```

That installs to `/Applications` and launches it. Or grab the `ClaudeUsage-app`
artifact from a [CI run](../../actions) — it's ad-hoc signed, so Gatekeeper will
refuse it until you clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine "/Applications/Claude Usage.app"
```

The widget shows up in the widget gallery once the app has run at least once.

## What it reads

Two sources, both already on your machine. Nothing is sent anywhere.

| Source | Gives |
|---|---|
| `api.anthropic.com/api/oauth/usage`, using the OAuth token Claude Code already stored | 5-hour and 7-day limit utilization, and when each resets |
| `~/.claude/projects/**/*.jsonl` | today / this week / current session token counts and estimated cost |

The token is read from the login Keychain (`Claude Code-credentials`), falling
back to `~/.claude/.credentials.json`. We never log in, never write credentials,
and never transmit anything except the one authenticated GET above.

macOS asks once for permission to read that Keychain item. "Always Allow" stops
it asking again.

## Architecture

A widget extension is sandboxed: it can't read `~/.claude`, can't reach the
Keychain, and has no timer. So it never fetches anything — the menu bar app
polls every 60s and writes a small snapshot file that the widget renders.

```
Sources/
  UsageCore/     data layer, no UI — shared by the app, the widget, and the CLI
  SharedViews/   the ring gauge and palette, shared by the app and the widget
  MenuBarApp/    MenuBarExtra, the 60s poller, settings
  Widget/        TimelineProvider and the three widget families
  UsageCLI/      prints the snapshot; the CI smoke test
```

`swift test` covers `UsageCore` with no Xcode involved. The app and widget bundle
is built by Xcode via XcodeGen, since SPM can't express an app that embeds an
extension. Both build systems compile `Sources/UsageCore` directly — there's no
framework target to embed and sign.

The snapshot file is written to **both** the App Group container and Application
Support, and read back from whichever is fresher. App Groups are a
provisioning-profile capability that may need a paid developer account;
Application Support always works but only for a non-sandboxed widget. Writing
both means the sandbox posture is one entitlement flip in `project.yml`, with no
code change.

## Developing without a Mac

Swift doesn't build on Windows, so CI is the compiler and the display:

```sh
gh run download <run-id> -n snapshots -D snapshots
```

`Tests/SnapshotTests` renders every view — three widget families, the menu
popover, settings — across light and dark and eight data states (typical, warn,
critical, overflow, no-token, stale, no-data), and CI uploads the 66 PNGs. That
makes visual iteration a normal part of the loop instead of a blocker.

### Unverified

What the snapshot loop cannot prove, and needs one pass on real hardware:

- The widget loads and appears in the widget gallery. This is the real risk —
  the widget extension ships **unsandboxed**, and if WidgetKit refuses to load
  it, set `com.apple.security.app-sandbox: true` for `ClaudeUsageWidget` in
  `project.yml` and the App Group path takes over.
- The Keychain consent prompt behaves, and the token actually reads.
- "Open at login" sticks — `SMAppService` needs a properly signed app.
- The popover's Refresh / Settings / Quit buttons. `ImageRenderer` draws
  interactive controls as unavailable, so they show as prohibition badges in
  every snapshot. Layout around them is real; the buttons themselves aren't.

## Try the data layer

Runs on any Mac with a Swift toolchain, no Xcode project needed:

```sh
swift run usage-cli           # human-readable summary
swift run usage-cli --json    # exactly what the widget will render
swift run usage-cli --write   # write the snapshot file to disk
```

## Cost accuracy

Costs are computed from token counts, because current Claude Code transcripts no
longer record a `costUSD` field. Cache writes are billed by TTL — 1.25x input for
the 5-minute cache and 2x for the 1-hour cache — and Claude Code writes almost
exclusively 1-hour entries. Collapsing both into the 5-minute rate (which the
Stream Deck plugin does) understates the real figure substantially.

On Pro/Max plans this is notional equivalent API spend, not money you were
charged. Rates live in `Sources/UsageCore/Pricing.swift`; edit them when
Anthropic changes pricing.

Scanning is incremental — per-file byte offsets, so a 60s poll re-reads only what
was appended rather than the multiple gigabytes an active `~/.claude/projects`
accumulates.

## License

MIT

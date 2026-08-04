# claude-usage-mac

Claude Code usage in the macOS menu bar and as a desktop widget — session and
weekly limit percentages, plus token counts and estimated cost.

A native port of [claude-usage-streamdeck-plugin](https://github.com/saeedkolivand/claude-usage-streamdeck-plugin)
for people who don't own a Stream Deck.

> **Status: in progress.** The data layer (`UsageCore` + `usage-cli`) is done.
> The menu bar app and widget are not built yet.

## What it reads

Two sources, both already on your machine. Nothing is sent anywhere.

| Source | Gives |
|---|---|
| `api.anthropic.com/api/oauth/usage`, using the OAuth token Claude Code already stored | 5-hour and 7-day limit utilization, and when each resets |
| `~/.claude/projects/**/*.jsonl` | today / this week / current session token counts and estimated cost |

The token is read from the login Keychain (`Claude Code-credentials`), falling
back to `~/.claude/.credentials.json`. We never log in, never write credentials,
and never transmit anything except the one authenticated GET above.

macOS will ask once for permission to read that Keychain item. "Always Allow"
stops it asking again.

## Try the data layer

```sh
swift run usage-cli           # human-readable summary
swift run usage-cli --json    # exactly what the widget will render
swift run usage-cli --write   # write the snapshot file to disk
```

## Architecture

A widget extension is sandboxed: it can't read `~/.claude`, can't reach the
Keychain, and has no timer. So it never fetches anything — the menu bar app
polls every 60s and writes a small snapshot file that the widget renders.

```
Sources/
  UsageCore/    data layer, no UI — shared by the app, the widget, and the CLI
  UsageCLI/     prints the snapshot; the CI smoke test
  MenuBarApp/   not built yet
  Widget/       not built yet
```

`swift test` covers `UsageCore`. The app and widget bundle is built by Xcode via
XcodeGen, since SPM can't express an app that embeds an extension.

## Cost accuracy

Costs are computed from token counts, because current Claude Code transcripts no
longer record a `costUSD` field. Cache writes are billed by TTL — 1.25x input
for the 5-minute cache and 2x for the 1-hour cache — and Claude Code writes
almost exclusively 1-hour entries. Collapsing both into the 5-minute rate (which
the Stream Deck plugin does) understates the real figure substantially.

On Pro/Max plans this is notional equivalent API spend, not money you were
charged. Rates live in `Sources/UsageCore/Pricing.swift`; edit them when
Anthropic changes pricing.

## License

MIT

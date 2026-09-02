# Where2Go Restart Plan

## Product outcome

The addon helps a player decide what to run next to obtain items from their
own preferred-item list. It ranks content by the share of its eligible reward
pool that consists of useful targets, then explains the items and the loot
specialization behind that result.

This is a planning baseline, not an implementation specification. Every phase
must be designed, tested, and verified in the WoW client before the next phase
starts.

## Scope

Two player intents are separate views:

1. **Direct drops**: rank Mythic+ dungeons and individual raid encounters by
   useful targets divided by that content's eligible item pool.
2. **Voidcore**: rank the content a player may choose to run for a Voidcore
   roll. Its pool and history rules are independent from direct drops.

The addon does not claim to know Blizzard's unpublished item drop rates. The
initial probability is an equal-outcome estimate and must be labelled as such.

## Delivery sequence

### Phase 1: Foundations

- Create the addon manifest, initialization, saved-variable schema, and a
  small test harness.
- Load a minimal, versioned source-data fixture for one dungeon and one raid.
- Render a static recommendation panel in the Dungeon and Raid Finder.

Acceptance: the addon loads without errors after `/reload`, and the panel is
visible and removable without changing game state.

### Phase 2: Preferred items and equipment comparison

- Store preferred items per character and per purpose.
- Read equipped items and compare candidates by upgrade track first, then item
  level, with explicit handling for rings and trinkets.
- Retain a higher-track candidate even when the player previously owned the
  same item ID at a lower track.

Acceptance: deterministic tests cover the comparison rules and a live-client
check confirms one higher-track candidate is shown.

### Phase 3: Direct-drop recommendations

- Build eligible pools per loot specialization.
- Rank Mythic+ per dungeon and raids per encounter.
- Show each result as one expandable card containing its title, target/pool
  estimate, recommended loot specialization, and target-item rows.

Acceptance: a fixture with known pool sizes produces the expected ordering;
the first results are expanded by default in the live panel.

### Phase 4: Voidcore recommendations

- Keep Voidcore history separate from general ownership.
- Remove only rewards already consumed by Voidcore from the Voidcore pool.
- Reuse the card presentation while retaining separate direct-drop and
  Voidcore views.

Acceptance: adding a known Voidcore reward changes only the Voidcore result
for its relevant pool.

### Phase 5: Data and release readiness

- Define seasonal data ingestion and validation.
- Add automated syntax and contract checks suitable for Windows development.
- Establish packaging, a clean-install smoke test, and a release checklist.

Acceptance: a packaged addon installs in a clean addon directory and passes
the documented smoke test.

## UX requirements

- Start with the ranked content choice, not a long item list.
- A Mythic+ result represents the whole dungeon.
- A raid result represents one boss encounter, while retaining its raid name
  for context.
- A card contains the result header and its target items as one visual unit.
- Keep wording concise; player-facing text may be localized.

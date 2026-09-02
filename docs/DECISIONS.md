# Product Decisions

## 2026-09-02: Restart from documentation only

The previous implementation is not the new baseline. Source code, generated
data, vendored libraries, and developer tooling are removed from `master` so
the next implementation can be designed from the product goal. The full prior
state remains recoverable from `codex/pre-restart-backup`.

## 2026-09-02: Core player question

Where2Go answers: “Given my preferred items, what content is the best use of
my next run?” It must rank content, not merely display valuable items.

## 2026-09-02: Equal-outcome probability model

Public boss-specific drop rates are not assumed available. Until a better
authoritative source exists, a result's direct-drop estimate is useful targets
divided by all eligible items in that content's pool. Every eligible outcome
has equal weight.

## 2026-09-02: Separate player intents

Direct-drop farming and Voidcore farming are distinct views. A player may run
the same content for different reasons, so neither view may alter the other's
ranking or history.

## 2026-09-02: Content granularity

Mythic+ is ranked per dungeon. Raids are ranked per boss encounter in every
view. A raid boss result includes the raid name for context but has its own
pool, probability, rank, expansion state, and item card.

## 2026-09-02: Preferred items and ownership

Preferred items are character-scoped. General ownership history alone must
not suppress an item ID because the same item can appear at different tracks
or difficulties. Whether a candidate remains useful is decided by its actual
comparison with equipped gear. Voidcore history is separate because a prior
Voidcore reward changes that system's repeatable pool.

## 2026-09-02: Presentation

The recommendation list is content-first. Each result is one expandable card
that contains its content label, target/pool estimate, recommended loot
specialization, and item rows. The first few recommendations open by default.

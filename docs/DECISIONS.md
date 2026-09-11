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

## 2026-09-10: Owned versions and recommendation usefulness

Both recommendation modes suppress a preferred target if equipped or
ordinary-bag gear is equal or better under the selected ownership rule.
The character-scoped toggle selects `ITEM` (default: exact item ID) or `SLOT`
(usable gear for the same slot). Compare recognized upgrade tracks first, then
actual item level when tracks are equal or unknown. Missing data does not prove
dominance. Compare every owned copy with each source-specific candidate; a
weaker copy or lower difficulty must not hide an upgrade. Bank and warband
storage are outside this lookup's scope.

For Slot comparisons, one unrelated ring or trinket must not suppress an
upgrade for the other slot: two distinct usable equal-or-better item IDs are
required. A matching equal-or-better item ID still satisfies the same-item
rule. Weapon comparisons use compatible equip-type families rather than
assuming one-handed, two-handed, shield and offhand items are interchangeable.
This is a conservative gear filter, not a simulation of unique-equipped
categories, weapon loadouts or secondary-stat value.

This refines the ownership decision above: current carried ownership is used,
not historical possession, and preferences remain saved. Suppression changes
the useful-target numerator only. Voidcore reward history continues to change
its eligible pool independently. Equipment and bag changes refresh the visible
recommendation panel.

## 2026-09-10: Direct-drop and Voidcore raid levels

Mythic raid direct-drop recommendations retain each boss's actual drop level:
Myth 1/6, 2/6, or 3/6 for bosses 1–6 and Myth 9/6 for the final two.
Voidcore raid rolls follow the equivalent Great Vault reward instead: Myth
6/6 at item level 334 for bosses 1–6 and Myth 9/6 at item level 344 for the
final two. The two ranking modes must carry separate item levels, ranks, and
bonus IDs without mutating shared direct-drop entries.

Encounter Journal links are source templates rather than authoritative for
the recommendation's calculated rank. Tooltip construction replaces only a
recognized upgrade-track bonus with the calculated source bonus, preserving
all other bonus IDs and trailing item-link fields. Successful links are
cached by item and requested rank; a transient missing link remains retryable.

## 2026-09-02: Presentation

The recommendation list is content-first. Each result is one expandable card
that contains its content label, target/pool estimate, recommended loot
specialization, and item rows.

## 2026-09-02: Card default state (supersedes "first few open by default")

All recommendation cards open by default, not just the first few. Decided
during Phase 3 planning when the player found a partially-collapsed list
harder to scan than a fully open one. Cards must still support collapsing
individually -- this only changes the initial state.

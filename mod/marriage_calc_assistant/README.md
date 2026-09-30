# Marriage Calculation Assistant 3.0.1

MCA adds a compact live score to each candidate in Crusader Kings III's
marriage picker. Higher means more **candidate gameplay potential under MCA's
designer weights**. It is not the AI's willingness to accept, a guaranteed
net benefit from a particular marriage, or a price that can be added to the
other spouse's score.

## What 3.0.1 fixes

The eight adapter component defaults are now zero-valued **formulas**, rather
than scalar constants. A controlled CK3 1.19 test with only those eight changes
restored AGOT:MCA's missing dragonrider contribution: Rhaenyra changed from
65 to **95 = 35 dynasty + 30 inheritable qualities + 30 dragonrider potential**
on both picker sides. Non-rider control scores were unchanged. No scoring
weights, adapter predicate, GUI or sorting logic changed.

This establishes the practical scalar-to-formula binding fix; it does not
establish the engine's internal constant-folding or duplicate-resolution
algorithm. Keep extension defaults in formula form when maintaining the ABI.

## What changes in 3.0

- Both picker sides now use the same five public candidate components:
  inheritable qualities, skills, age-based reproductive potential, dynastic
  prestige potential and explicit claim potential.
- Court position, personal attachment, arranger opinion, an older relative's
  willingness to marry, reluctance to lose claims or an inspiration, and
  acceptance bonuses for lieges or heirs no longer affect the core score.
  The eight old component values remain zero-valued compatibility stubs;
  their localization keys are retained, but active totals do not call those
  values.
- Alliance metadata, score sorting, row-selection identity and the readable
  18 px score placement are retained. The calculation does not change actual
  marriage acceptance or any game rule.

The 3.0 formula and the 3.0.1 adapter fix have passed scoped in-game tests at
100% UI scale: native breakdown arithmetic, score sorting and moved-row
selection. The dragonrider contribution was observed on P and the native R
pinned-recipient row. At 125% UI scale, the user also reported successful checks of both picker
sides, score and tooltip visibility, sorting, scrolling and row selection
on 2026-09-30. Closed logs had no matching family regressions. This is
user-reported visual acceptance, not independent assistant observation or
exhaustive scenario coverage. The detailed record is `tests/mca/SMOKE.md`
in the source repository.

## Existing score and sorting behavior

- Scores remain pure `script_value` calculations. MCA never stamps candidates
  or mutates the engine's marriage list. Optional score sorting uses a
  player-owned snapshot and projects the original native list items.
- MCA no longer overrides `arrange_marriage_interaction` or
  `marry_off_interaction`.
- The global character-list row is untouched. MCA derives one marriage-only
  row for the native list, sorted list and native pinned-player entry.
- Score visibility uses the marriage window's actor and active picker side,
  with candidate availability checks. It does not compare translated role
  labels or depend on a Parley session variable; localized labels can require
  a character context that a bare GUI localization call does not supply.
- Hovering the number opens the engine's native script-value breakdown, whose
  described lines sum to the displayed badge.
- The score sits beside age/health under the candidate's name, labelled MCA,
  in the same 18 px font as the name. Its 112 px hover area is inside the
  existing name column, away from the scrollbar. Native relationship text
  follows it; the 630 px picker geometry and skill/trait panels are unchanged.
- Potential-alliance value uses the marriage window's own C++ metadata. It is
  `round(clamp(base * partner.max_strength / player.current_strength, 1, 100))`.
  The strength ratio is capped at 2.5 and the denominator is at least one.
  The default base is 40; these are MCA comparison points, not engine
  acceptance modifiers or a guarantee that every soldier will join a war.

## Using score sorting

The picker opens in its normal mode. Set the native filters, close the filter
panel, then press **MCA: by score**. The current candidate list is sorted from
highest to lowest MCA score, including the same potential-alliance metadata
as the displayed number. Equal scores retain the current native order.
Characters without an available score go last. The engine's separate pinned
player row stays pinned and is not part of the sortable candidate list.

**Default list** returns to the engine's ordering and enables its filter/sort
controls again. Closing the picker, selecting a spouse, changing the active
side or marriage type, or detecting changed candidates/scores clears the
snapshot. Reopen the picker or enable MCA again to recalculate. The mode does
not send a proposal, alter acceptance, or change who a row selects.

## Shared candidate-potential formula

`score = G + S + F + D + C + A + adapter components`

The five candidate components `G`, `S`, `F`, `D` and `C` are identical for P
and R. Alliance `A` is included only when the native row metadata reports a
potential alliance. Normal display, alliance display, raw totals and score
sorting all reuse these components exactly once. Each active component has
its own described native breakdown row; the displayed rows sum to the badge.

The point scales below are explicit design choices grounded in public game
mechanics. The retired acceptance components make no contribution.

### G: visible inheritable qualities

This component evaluates the candidate's explicit, active inheritable
qualities. Good qualities raise the score and harmful ones lower it on both
sides. It does not price the offering household's loss of a courtier.

| Qualities | MCA points |
| --- | ---: |
| Intelligence, beauty and physique: positive levels 1 / 2 / 3 | +10 / +20 / +30 |
| The corresponding negative levels 1 / 2 / 3 | -10 / -20 / -30 |
| Pure-blooded; fecund | +10 each |
| Inbred; infertile | -50 each |
| Bleeder | -30 |
| Spindly; wheezing; clubfooted; hunchbacked | -10 each |
| Lisping; stuttering | -5 each |

These are balance weights for inheritable potential, not engine inheritance
probabilities or a promise that children will acquire a trait. Each tiered
family contributes its strongest present positive/negative level; independent
qualities add together. All else equal, each positive tier beats neutral,
which beats each negative tier. Other benefits, such as an alliance, can
still outweigh these points in the total.

Only explicit active traits are read. Hidden/recessive genetics, real parentage,
pair-relatedness and reinforcement between two parents are not evaluated.
The score does not evaluate the selected other spouse's genetics, so this is
not a complete estimate of offspring or of a particular marriage. In
particular, the infertile penalty does not estimate birth probability; AGOT
and vanilla give that trait different fertility effects. Age/other fertility
constraints are not used to rescale this component.

Giant, dwarf, albino and scaly remain neutral in this narrow component because
their effects have contextual tradeoffs; the psychiatric genetic/acquired
variants are deferred until their visible distinction is verified. Acquired
strong, shrewd, weak and dull are not counted as inheritable.

### S: skill potential

For a capable candidate of effective age 16 or older:

`S = min(30, sum(max(1, floor(skill / 5))))`

The sum uses diplomacy, martial, stewardship, intrigue and learning. Younger
or incapable candidates receive zero. This is based on the unmodified
assist-spouse skill contribution, with a designer cap of 30 points. It does
not predict a child's adult skills, assume the candidate will be an eligible
councillor, or include council-task, perk and cultural multipliers. In
particular, it is potential rather than a promise that the player receives
all five contributions after marrying this candidate.

### F: age-based reproductive potential

This is a 0–20 age index, **not a birth probability**. It follows the public
sex/age fertility bands and reads engine `effective_age`, not calendar age
or the character's hidden fertility or health values.

| Effective age | Female points | Male points |
| --- | ---: | ---: |
| Below 16 | 0 | 0 |
| 16–25 | 20 | 20 |
| 26–30 | 18 | 20 |
| 31–35 | 14 | 20 |
| 36–40 | 10 | 18 |
| 41–45 | 7 | 16 |
| 46–50 | 2 with fecund, otherwise 0 | 16 |
| 51–60 | 0 | 14 |
| 61–70 | 0 | 12 |
| 71 or older | 0 | 10 |

Incapable, celibate, `eunuch_1` and `beardless_eunuch` candidates receive zero.
Fecund's public five additional fertility years explain the female 46–50
extension. Effective age also respects the engine's handling of immortality;
MCA does not substitute chronological age. A child receives zero for current
reproductive potential, not a prediction of lifelong childlessness.

The index does not reconstruct hidden fertility, model the other parent,
existing children, pregnancy timing or all fertility modifiers. Inheritable
qualities remain a separate potential component even when this index is
zero. The inherited-quality weights for fecund/infertile are not additional
birth probabilities.

### D: dynastic prestige potential

MCA scales the engine's dynasty marriage-prestige table
`[-100, 0, 100, 200, 300, 400, 500, 600, 700, 800, 900]` at 20 prestige per
point. The result is clamped to −5…+45; a candidate without a dynasty receives
−5. This measures the candidate's dynastic-prestige opportunity, not the
actual prestige reward for the selected pair. Rank differences, the other
spouse, marriage form and religious rules can change or remove that reward.
It is not a monthly renown estimate.

### C: explicit claim potential

Only the strongest explicit (non-implicit) claim contributes; portfolios are
not summed. A claim's title tier sets the base points:

| Title tier | Unpressed claim | Pressed claim |
| --- | ---: | ---: |
| Barony | 1 | 2 |
| County | 2 | 4 |
| Duchy | 4 | 8 |
| Kingdom | 8 | 16 |
| Empire or higher | 12 | 24 |

Pressed claims receive twice the points, with a total cap of 24. This
distinguishes their inheritance potential from unpressed claims without
pretending that a marriage transfers either a title or a claim to the
player. Implicit claims, the succession queue, claimant eligibility, laws,
matrilineal outcomes and the practical ability to press a claim are not
solved. A valuable claim is an opportunity, not guaranteed land.

### Coverage and mechanic sources

The age bands and dynasty table come from installed CK3 1.19
`common/defines/00_defines.txt`; public trait effects and fertility-year
extensions are in `common/traits/00_traits.txt`. The skill baseline is from
`common/script_values/99_spouse_councillor_values.txt`. MCA's exact component
implementation is in `common/script_values/tnt_ma_52_grade.txt`.

The formula intentionally does not compute full pair utility: no hidden
genes, real parentage, hidden health/fertility, predicted births, inheritance
queue, title transfer, exact marriage prestige or guaranteed marginal renown.
Existing titles and being an heir do not receive a separate blanket bonus.
Potential alliance strength and claims are visible opportunities with the
limits above, not promises of control or acquisition. The chosen weights
make those opportunities comparable for sorting; they are not quantities in
a common engine resource.

### Snapshot ownership and limits

`common/scripted_guis/tnt_ma_sort.txt` privately owns start, collect, finalize,
clear and read-only context-validation actions. Four private capture values in
`common/script_values/tnt_ma_sort_capture.txt` reuse the visible score and
availability checks; there is no second scoring formula.

The snapshot is **saveable script state on the local player**, not transient
engine memory. Nothing is written to candidates. Normal GUI lifecycle cleanup
removes all 12 scalar variables and six lists. If the game is saved while the
picker is open, reopening it clears stale state. Disabling the mod before
cleanup can leave inert player variables in that save; close the picker
before saving or uninstalling. There is no global sweeper or new on-action.

All private snapshot names start with `tnt_ma_sort_`:

- Scalars: `state`, `expected`, `received`, `partner`, `secondary_actor`,
  `secondary_recipient`, `side`, `matrilineal`, `day`, `direction`, `cursor`,
  `output_count`.
- Lists: `seen`, `packed`, `indices`, `keys`, `keys_by_index`, `candidates`.

Capture accepts 1–9,999 entries and integer scores from −10,000 to +10,000.
It checks the complete index permutation and exact numeric round-trips before
showing the sorted list. Both visible rows and a full-list watcher compare
fresh scores and actual character references against the snapshot, including
changes that leave the list length unchanged. Invalid snapshots fall back to
the native list rather than exposing an unverified selection.

## Extension contract

`common/script_values/tnt_ma_00_adapter_defaults.txt` owns eight overridable
component slots and one calibration default:

- `tnt_ma_adapter_p_c1_value` through `tnt_ma_adapter_p_c4_value` = `0`
- `tnt_ma_adapter_r_c1_value` through `tnt_ma_adapter_r_c4_value` = `0`
- `tnt_ma_alliance_base_value = 40`

All eight component defaults use `{ value = 0 }`, not scalar `= 0`.
Their names, numeric defaults and candidate-scope contract are unchanged.

Total-conversion adapters may override those exact names in a later-sorting
script-value file. Components are signed deltas where higher is better for the
local player. They must be deterministic integers and must not write
persistent state. Every nonzero component must supply its matching localized
description key (`tnt_ma_adapter_p_c1` through `_c4`, or the R equivalents).
Core-owned `tnt_ma_adapter_p_value` and `tnt_ma_adapter_r_value` are derived
aggregates retained for raw/legacy callers and must not be overridden.

GUI-facing values are:

- `tnt_ma_grade_p_value`
- `tnt_ma_grade_p_alliance_value`
- `tnt_ma_grade_r_value`
- `tnt_ma_grade_r_alliance_value`
- `tnt_spouse_grade_value` (deprecated compatibility wrapper; no alliance)

For P, root is the candidate and the GUI supplies standard `actor` (player)
plus `tnt_gr_p` (other arranger). The public wrappers immediately normalise
`actor` into temporary `tnt_gr_me`, preserving the component/adapter ABI. For
R, root is the candidate; MCA also resolves `tnt_gr_p` and `tnt_gr_side` from
`root.matchmaker`. Shared candidate components do not read the arranger's
opinion, court relationships or inspiration state. P/R scope availability
and the existing adapter ABI are preserved even though the base formula is
now symmetric.

AGOT:MCA 2.2 uses the same candidate-potential meaning: a publicly current
dragonrider contributes +30 on both sides; old blood-tier and inspiration
corrections are zero, and alliance calibration is 40. This is a designer
weight for a current living dragon bond, not a promise of military readiness,
dragon ownership or control after marriage. The adapter owns those overrides
and their localized descriptions; MCA does not inspect AGOT-only traits.
Use this release with AGOT:MCA 2.2 or a newer potential-model adapter, not
2.1: the older adapter still adds asymmetric acceptance-derived penalties.

Parley remains the sole owner of the five legacy addon hooks. MCA 3.x neither
defines nor calls them. Old 1.x candidate stamps in existing saves are inert:
3.x never reads them. They are deliberately left untouched because CK3 1.19
reports references to variables whose setters no longer exist as validation
errors, even when those references only try to remove legacy data.

## Compatibility surface

MCA extends CK3 1.19's `gui/interaction_marriage.gui` with the marriage-only row
and optional sorted-list controls, capture, projection and lifecycle guards.
This is its sole vanilla-path override. Another mod replacing the same file
needs a functional compatibility patch; the old two-line patch is no longer
sufficient. Native 630 px list geometry and original row selection callbacks
are retained. Mods that only replace
`gui/shared/lists.gui` remain compatible when their row retains the vanilla
`character_relation` block in the name/age column.

Load order: Parley, MCA, then an optional MCA adapter. The 2.1 component/value
ABI is unchanged. No Parley or AGOT files are owned by this release.

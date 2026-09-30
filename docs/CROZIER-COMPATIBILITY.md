# MCA 3.1: CK3 1.20 source adaptation

Reviewed on 2026-09-30 against the installed CK3 1.20.0.2 source. This record
covers the source rebase, model results and bounded RC7 native UI observations
below. It does not carry forward the CK3 1.19 / AGOT smoke as CK3 1.20 evidence
or establish compatibility beyond the tested cases.

## Visible behavior and ownership

MCA now uses vanilla's `GetPuppetOrActor` for the marriage window's small left
portrait. Direct arrangements by the local player retain scores and sorting.
For a puppet arrangement, MCA hides the player-perspective scores and disables
score sorting; the native marriage list and its eligibility rules remain in
control. Supporting a puppet's own valuation would require a separate score
perspective and adapter contract, so this update does not guess one.

Both the actual actor and effective arranger must equal `GetPlayer` before the
four score owners or sort-start button are available. All eight sorter context
packets pass the fresh effective arranger. Start, collect and context validation
compare that character with the existing player owner. The read-only context
check rejects an arranger change, which activates the existing clear controller;
late collect callbacks for another arranger cannot append to the player snapshot.
No extra persistent variable or candidate stamp was introduced. Clear, native
selection callbacks, index/character identity checks and stable ties are retained.

The RC6 native picker run exposed repeated `Animation triggered has no valid
state properties or sound effects` diagnostics during sorting. Twelve existing
sorter states had only conditions/callbacks, without an animation property. They
now each carry `scale = 1`, following the native name-plus-identity-scale state
in `gui/hud_notification_templates.gui:1469-1472`. This keeps the default
transform; no duration, opacity, sound, visibility, condition or callback changes
were added. Each affected owner and the inherited character-list vbox have no
conflicting scale. Removing the twelve property lines and two comments exactly
reproduces the prior GUI. The frozen current patch and manifest include this
reviewed change; historical contracts remain untouched. RC7's native picker
sequence below completed with no animation-state diagnostics, while capture,
selection and the exercised cleanup transitions continued to work.

## Upstream review

The retained CK3 1.19 marriage GUI and current CK3 1.20.0.2 file differ on one
line: `left_small_portrait` changes `GetActor` to `GetPuppetOrActor`. The new
frozen patch includes that upstream line without overriding it. The original
MCA patch and shared 2.2/2.3 contracts remain historical artifacts. The current
shared contract is `tnt_mca_31_marriage_contract.json`, with a `1.20.*` metadata
guard and exact upstream / patch / reconstruction hashes.

Current vanilla marriage GUI byte SHA-256:
`8AB7AA6C6B4B778E8AAD62B06768B166996E9DAB5B5400CDDD56C7F5822CF6AD`.

Current vanilla `gui/shared/lists.gui` byte SHA-256:
`71C6DD9036ED54D53D95E6229782924325F262D208F4E971775237BD4852E5AC`.
The full older lists file was unavailable, so a whole-file old/new comparison
is not claimed. The current inherited `widget_character_list_item` was reviewed:
character context, native OnClick/IsSelectable/reason callbacks, relation and
skills seams, 320 px name column and 12 px scrollbar still support MCA's existing
630 px row geometry. MCA continues to override only `character_relation`.

MCA does not own marriage interactions or eligibility triggers, and its current
score values do not query faith, doctrines or rites. The 1.20 marriage triggers
now use rite-aware native checks; MCA leaves them intact. Alliance presence for
both score display and capture still comes from the native
`CharacterListItem.GetOtherCharacterItems` datamodel. The five shared potential
components, eight formula-zero adapter defaults and all localized score strings
are unchanged. The current vanilla fertility bands, Fecund extension and dynasty
marriage-prestige table still match the documented potential inputs.

## Source and model results

Commands use the explicit roots shown in `dev.md`:

- `tests/mca/check_source.ps1`: 8/8 PASS, including exact patch reconstruction.
- `tests/mca/test_crozier.py`: 10/10 PASS. Evaluates actual start/collect/context
  predicates for direct, puppet and missing arrangers; checks identity distinct
  from equal numeric state, ready-state invalidation, late callbacks, native row
  callbacks and native alliance metadata. All twelve callback states require
  only the native identity-scale property plus their original callback/condition
  fields. Eight active/idle mutations (missing property, scale zero, opacity or
  duration substituted) are rejected.
- `tests/mca/test_genetics.py`: 12/12 PASS.
- `tests/mca/test_potential.py`: 15/15 PASS.
- `tests/mca/test_sort_math.ps1`: PASS, 772,667 assertions.
- Shared `Test-McaSortContract`: PASS with no faults.
- Shared `tnt_frozen_sync_check.ps1`: PASS against current vanilla and the
  installed AGOT inherited row. An AGOT seam check is not AGOT 1.20 support.
- Shared `tnt_family_gate.ps1`: all nine checks PASS over the current three
  developer trees, current vanilla and the installed AGOT source.

Negative fixtures removed the collect arranger comparison, removed the context
arranger comparison, omitted a GUI arranger packet, or restored the old portrait
API. The new regression rejected all four. The shared structural sorter also
rejected the collect mutation. The frozen checker rejected both the retained
1.19 vanilla baseline and a reverted MCA portrait against the current baseline.
Local mutation logs are under
`C:/Users/Pavel/Documents/ChatGPT/ck3-mods-artifacts/mca-crozier-negative-20260930`;
the release workspace evidence folder contains `mca-negative-results.json`.

## RC7 native UI observations

The isolated CK3 1.20.0.2 RC7 playset contained Parley and MCA, with no harness
or AGOT. The tested MCA marriage GUI byte SHA-256 was
`AA033AE800C5F23ED7BFBFA58FFAC6A7E972B796498F9FD9738778087948163E`.
The following cases were observed in the native marriage picker:

| Case | Observed result |
| --- | --- |
| Ali's Find Spouse list, native count 452 of 468 | MCA sorting placed Khatun-e-Kermani +62, Bahiyya +41 and Mamam +40 first. |
| Score tooltip and selected identity | Khatun's tooltip showed skill +6, age +20, dynasty +20, claims +8 and alliance +8, totaling +62. Her row's 3,914 allied troops matched the selected marriage confirmation. |
| Native list and filter transitions | Back reset to native order. Enabling matrilineal changed the native count to 461 of 477; sorting worked on the rebuilt list. Default list restored Bahiyya first. |
| Close and reopen | Reopening for Amr returned to native order with matrilineal off. |
| Player-side picker | The one-candidate Gulpari +16 list sorted successfully. |
| Recipient-side picker | The five-candidate list sorted Amr +36, Abd al-Qadir +23 and Sabba +20 first. Selecting Abd chose that character, then the asynchronous switch returned to the player-side native list with Gulpari +16. |

At completion of this sequence, `error.log` contained zero `Animation triggered
has no valid state properties or sound effects` records and zero `tnt_ma_`
diagnostics; `gui_warnings.log` was empty. This confirms suppression of the RC6
sorter warning bursts for the tested lists, not a claim that the whole playset's
error log is empty. The native UI checks exercised the identity-scale change
without the event harness.

Screenshots are retained in the release workspace under
`verification-evidence/crozier-2026-09-30/engine/screenshots/`:
`rc7-mca-large-list-tooltip.png`, `rc7-mca-large-list-selection.png`,
`rc7-mca-filter-resort.png`, `rc7-mca-r-sorted.png` and
`rc7-mca-r-selection.png`. The sequence observations and runtime log review are
separate from the source/model assertions above.

RC7 remained rejected as a combined candidate because the later natural
AI-world smoke found a Parley vassalization alias defect. RC8 changes that
Parley caller while retaining the exact tested MCA runtime. Its separate
12-assertion native-mutation harness and no-harness campaign through
24 January 1179 passed; Amr's natural fealty offer executed for 743 gold at +2.
Neither the repaired scope failure nor MCA animation diagnostics recurred.
The clean-playset log retains 40 classified startup diagnostics and seven
native records that reproduce exactly apart from wall-clock timestamps in an
all-mods-off run of the same original save. These results support the bounded
vanilla Parley/MCA check, not a globally clean log or new MCA coverage. See Parley's
[compatibility record](../../parley/docs/CK3-1.20-COMPATIBILITY.md) for the
separate RC8 fixture warnings, natural-offer evidence and vanilla control.

## Remaining engine coverage

Native puppet activation and the engine's actual `GetPuppetOrActor` population
remain untested in the UI. A puppet arrangement must retain the native list
without MCA scores or sorting, and direct-to-puppet transitions must clear the
player snapshot; source tests and controlled saved-scope checks do not prove
those native paths. Time advancement with an active sorted snapshot, save/reload
cleanup, arbitrary filter/partner changes and all possible callback timings are
also outside this bounded sequence. AGOT cases require an upstream version
supporting CK3 1.20.

The immutable RC3 package, historical manifests and release-input/package pins
are unchanged. Publication remains a separate release decision.

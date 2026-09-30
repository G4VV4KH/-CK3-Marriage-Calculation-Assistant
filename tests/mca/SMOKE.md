# MCA verification record

## MCA 3.0.1: user-reported 125% interface acceptance, 2026-09-30

The user completed the instructed test with AGOT, its Russian translation,
Parley, MCA 3.0.1 and AGOT:MCA on the Viserys 106 save, temporarily using 125%
GUI scale. The requested checks covered both picker sides, fully visible
scores clear of the scrollbar, tooltips and controls fitting on screen,
MCA sorting, scrolling and selection of the displayed character. The user
confirmed the procedure as a whole: **"всё правильно"** (everything correct).

This is **user-reported visual PASS**, not independent assistant visual
verification: no screenshot or direct observation of this 125% session was
supplied. The instructions called for no time advancement or proposal,
restoring the preferred scale afterwards and exiting without saving.

After the session, the coordinated task confirmed CK3 process count zero.
Fresh closed `error.log` and `gui_warnings.log` contained zero `tnt_`/`agot_ma_`
matches and zero matches for the known Character.IsFemale, unknown
trigger/effect and used-but-never-set regressions. This is not a whole-game
clean-log claim. Evidence: `verification.json` and logs under
`C:/Users/Pavel/Documents/ChatGPT/ck3-mods-artifacts/2026-09-30-mca301-user-125`.

Only this verification record was updated; runtime files, README and release
manifests were unchanged, and no additional game session was launched.

## MCA 3.0.1: measured adapter-binding fix, 2026-09-30

In the existing AGOT + translation + Parley + MCA + AGOT:MCA playset, Rhaenyra
at paused 106.4.18 initially scored **65 = 35 dynasty + 30 genetics**, despite
the visible living Syrax bond and AGOT's native tamed-dragon status. AGOT:MCA
2.2.0 was enabled with its expected runtime hash. This exposed a gap in the
previous nonzero-adapter coverage; source-only seam checks had not detected it.

The controlled runtime candidate changed **only eight core adapter defaults**
from scalar `= 0` to formula `= { value = 0 }`. Its defaults SHA-256 was
`AFB36BE8FBC9887F8C9F64ADF872228E6F91CB8E4E4485FA3615A13EBCE5A4AE`.
AGOT predicates, weights, aliases, all scoring wrappers, GUI and sorting code
were unchanged. Reversing exactly those eight substitutions reproduced the
previous defaults byte-for-byte. Source/live parity was 18/18.

After a fresh launch of the exact saved case, the coordinated Parley task
observed:

- P Rhaenyra: **95 = 35 dynasty + 30 genetics + 30 localized dragonrider
  potential**, in both the score and its native breakdown.
- MCA sorting moved Rhaenyra above unchanged Larys 74; selecting the moved
  row confirmed Rhaenyra. Morden 42 and Orryn 34 were unchanged controls.
- Opening Arrange Marriage from Rhaenyra, choosing Larys on P and reopening
  the R picker showed the native pinned recipient Rhaenyra at **95**, with
  the same three breakdown components. Other R candidates included Korianna
  26 and Rissa 10; changing the selected candidate and reopening preserved
  the correct pinned-recipient value. No proposal was sent.
- A separate R Laenor row showed **73 = 25 dynasty + 20 genetics + 28 alliance**.
  This verifies an alliance-bearing row, **not** a Laenor dragonrider bonus;
  his full rider/housing predicate was not established.

This controlled result supports the scalar-to-formula seam fix. It does not
prove a specific internal C++ constant-folding or duplicate-resolution
algorithm, nor justify changing the AGOT rider condition. The 3.0.1 promotion
adds only release metadata, explanatory comments, documentation and exact
formula-default regression checks around the tested runtime logic.

CK3 PID 12456 exited normally with process count zero. No proposals, time
advancement or saves after the test were made. Closed `error.log` and
`gui_warnings.log` contain zero `tnt_`/`agot_ma_` family matches. The playset
remained `9FE23D6880E712379B7C26C3953D368817355C28F06497A1A8F46954C0315303`.
The saved diagnostic case `Король_Визерис_(Железный_трон)_8106_04_18.ck3`
remained `FE4A778CBEAD9A89386984D9E41D8CDBC9B80876472B3FB9B90BEA3D6F23A34D`.

Before/after evidence is archived under
`C:/Users/Pavel/Documents/ChatGPT/ck3-mods-artifacts/2026-09-30-dragon-bonus`.
The historical 3.0.0 manifest is preserved; 3.0.1 has a separate manifest.
The nonzero R adapter observation was a native pinned-recipient row, not an
exhaustive sorted-R candidate matrix. This controlled run did not test 125%
UI scale; the subsequent user-reported acceptance is recorded above.

## MCA 3.0.0: coordinated runtime smoke, 2026-09-30

The shared candidate-potential model replaces the asymmetric acceptance-derived
components. Its five direct components are visible inheritable qualities,
practical skills, age opportunity, dynasty prestige potential and the strongest
explicit claim. Eight old component names remain exact zero stubs and have no
active consumers. The alliance gate, sorting and GUI geometry are unchanged.

Source checks pass 8/8 in PowerShell 5 and 7. Genetics tests pass 12/12 and the
strict actual-source potential model passes 15/15 (including negative grammar
fixtures, effective-age boundaries and explicit-only claim portfolios). The
sorting arithmetic model passes 772,667 assertions. These results do not prove
the new script-value claim iterator or native breakdown inside CK3.

The coordinated Parley task subsequently performed the in-game test below.
Core runtime commit: `2c7a5d230aaf4fb98cf0801a74e060950c8139b1`.
AGOT:MCA 2.2.0 commit: `0718072bcc5940b7481119315c114e6fb09de134`.
Environment: CK3 1.19.0.6, Russian UI, 1920x1080, GUI scale 100%.
Existing playset: AGOT, AGOT Russian translation, Parley, MCA, AGOT:MCA.
The game remained paused at 8082.1.1 throughout; no proposal was sent.

Observed native breakdowns:

- P Edmar Serrett: **46 = 8 skills + 20 age + 10 dynasty + 8 claims**.
- P Ellena Eldridge: **26 = 8 skills + 14 age + 4 claims**.
- P Viserra Targaryen: **65 = 35 dynasty + 30 inheritable qualities**.
- R Sylva Whistler: **15 = 6 skills + 7 age + 2 claims**.

Sorting and selection:

- P sorted order began Viserra 65, Rhaenys 55, Edmar 46, Daemon 45.
  Selecting moved Edmar in third position confirmed Edmar, not the character
  formerly at that native index.
- R native order Ammena 0 / Sylva 15 became Sylva 15 / Ammena 0. Selecting
  moved Sylva confirmed the correct Edmar + Sylva pair. The confirmation was
  canceled without proposing a marriage. Native acceptance remained a separate
  **-15**, not the MCA candidate score.
- None of the eight retired component labels appeared in observed breakdowns.
  Scores and native content were readable, inside the picker and clear of its
  scrollbar at 100% scale.

After normal desktop exit with exit-save unchecked, CK3 process count was zero.
The closed fresh error log had zero matches for `tnt_`, `agot_ma_`,
`Character.IsFemale`, unknown trigger/effect, invalid scope or used-but-never-set
warnings. `gui_warnings.log` had zero family matches. Unrelated vanilla/AGOT
GUI, localization, government and animation errors remain: this is not a claim
that the whole game log is clean.

Combined family gates passed 9/9 in PowerShell 5 and 7 and against live files;
the frozen GUI check passed. Live/source parity was 18/18 MCA and 12/12 adapter,
with zero SHA mismatches. Adapter tests passed 16/16; all nine family-gate
negative mutation fixtures were rejected.

Unchanged SHA-256 values after this test:

- `dlc_load.json`: `9FE23D6880E712379B7C26C3953D368817355C28F06497A1A8F46954C0315303`
- `autosave_exit.ck3`: `75A3A306ED39C43428A66BA79194E3F0C0716857B387D2E3386AD797748885C1`
- `sep2.ck3`: `F3B63FC0575E069E076AED6D0A8C86E7E71E0FEB3DCE6A8AC6DA617C3D52F1A8`

Archived logs, family gate output and the structured verification record:
`C:/Users/Pavel/Documents/ChatGPT/ck3-mods-artifacts/2026-09-30-mca30-smoke`.

**Not covered in this run:** a nonzero current-dragonrider adapter row, 125%
GUI scale, an alliance-bearing row, or an exhaustive pressed/unpressed claim
runtime matrix. No save data was manufactured to obtain those cases.

## MCA 2.3.0: runtime pending

The 2.3 source adds visible inheritable candidate qualities and a separate
marriage-local neutral left spouse label. Source tests do not establish
engine parser, native breakdown or label regression results. No CK3 launch
was performed during installation. The 2.2 evidence below is historical.

The next short in-game test should:

- Open arrange marriage with an unselected left spouse; leave the picker open
  for at least seven seconds, then select and clear a candidate. Check fresh
  logs for missing Character context and actor-secondary label errors.
- Hover a candidate with a visible scored trait. Confirm the new localized
  row contributes the documented amount and the breakdown sums to the badge.
- Repeat on both picker sides, including alliance and non-alliance cases when
  available. Compare candidates with otherwise similar components; differing
  alliance, standing or other components can still outweigh genetics.
- Enable MCA sorting, verify descending displayed scores, and confirm a moved
  row selects the shown character. Cancel without sending a proposal.

Current static genetics tests: 12/12, including all 343 valid combinations of
the three tiered trait families. No hidden genetics, inheritance probability,
fertility simulation or offspring prediction is claimed.

## MCA 2.2 historical runtime evidence

Environment: CK3 1.19.0.6, vanilla with local Parley and MCA, Russian UI,
1920x1080. Tests use the existing paused 1188-01-01 save. No proposal, marriage,
time advancement or save is permitted. AGOT runtime is not covered here.

## Proven prototype (run 10, 2026-09-30)

- Collected all 620 R candidates without scrolling. Sorted scores descended
  +14, +14, +12, +10. Tooltip: +14 = +13 +1.
- Selected the moved Niluefer row: confirmation named Niluefer, not the
  character formerly occupying that native index. No proposal sent.
- Reset and repeated capture; reversed the native order with the same 620
  entries and re-captured. Equal-score candidates followed the new native
  order rather than a stale snapshot.
- Applied native inheritable-trait filter: 30 candidates, all collected and
  sorted. Filter panel must be closed before MCA can be enabled.
- Changed matrilineality: native list restored. Closed/reopened an active
  MCA picker: native mode restored.
- P side with two sortable candidates: native Musa -34 / Faisal -24 became
  Faisal -24 / Musa -34. Selecting moved Faisal named Faisal in confirmation.
  The separate native pinned-player entry stayed pinned.
- Readable 18 px score under the name at 90% UI scale; native skills/traits
  remain visible and the score does not overlap the scrollbar.
- Closed without saving. Three autosave hashes unchanged; original playset
  restored byte-exact. Fresh family score/sort/GUI namespace error matches: 0.

Production promotion changes only diagnostic logs/comments and localized
control text; capture, projection and selection logic are unchanged.

## Installed production (run 11, 2026-09-30)

- Fresh launch with only Parley and installed MCA 2.2.0; no probe overlay.
- Native list contained 620 R candidates. MCA mode sorted the complete list
  +14, +14, +12, +10 without scrolling to collect candidates.
- Moved Niluefer selection again named Niluefer in confirmation. No proposal
  was sent. Her native breakdown was +14 = +13 aging relative +1 alliance.
- Russian controls, active-mode label and help tooltip were localized.
- At both 90% and 100% UI scale, the picker fit the 1920x1080 screen, the
  18 px score was readable below the name, and native skills/traits and the
  scrollbar remained clear. Sorting was repeated successfully at 100%.
- Restored the original 90% scale through the settings dialog and confirmed
  persisted GUI scale 0.9. Exited to desktop with exit-save unchecked.
- CK3 process count 0. Closed fresh error log: 0 matches for family score,
  scope, sorter, marriage GUI and preflight identifiers. Unrelated game-log
  noise is not represented as a clean whole-game parser result.
- Original playset remained byte-exact, SHA-256
  `9996CE3ADBD70430D2CBA8C1E453D7498733555E40E9DCCA907C7EA7BDB37B3C`.
  Three pre-existing autosaves retained their exact hashes:

  - autosave: `73853F67E7B79C1CBC70E17CE341DC33835933DA9C7DF625BC1C05ABC3BCBF66`
  - autosave_1: `1E4AEB1A6092055371DB8F183F86B66C292DABF8AE52F918DB59A282DC85D0F7`
  - autosave_2: `3D29A5F4E8D9526ECE135843A676B899221E5024F331FDEE71AD73D43518778F`

The disabled temporary probe launcher was removed after shutdown. Probe
sources and archived logs remain outside the release runtime inventory.

## Static checks

`test_sort_math.ps1` exercises the integer model, stable ordering, full index
permutations, both callback directions, reference-slot mapping and rejected
duplicate/non-monotonic callbacks: 772,667 assertions pass. This is not a CK3
parser or UI simulation.

`check_source.ps1` checks the source contract and frozen marriage GUI against
the approved native diff. This does not replace an in-engine smoke test.

## MCA 2.2 historical coverage boundaries

No induced background same-count character substitution, save/load of an open
snapshot, unpaused day change, multiplayer, 9,999-entry runtime stress test,
125% UI layout, or AGOT renderer/nonzero adapter hover has been performed.
Safety guards for these cases are source-reviewed, not runtime-certified.

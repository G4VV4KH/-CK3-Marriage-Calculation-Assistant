# Contributing to Marriage Calculation Assistant

MCA 3.0.1 source is in `mod/marriage_calc_assistant/`; its current scoring, sorting and extension contract is documented in that folder's `README.md`. Keep a pull request focused, explain the visible before/after behavior, and distinguish source/model evidence from game observations.

## Ownership

MCA owns the candidate score, marriage-only row and private player sorting snapshot. It does not change marriage acceptance or stamp scores onto candidates. Both picker sides share the five core potential components; alliance metadata and optional adapter components are added through their existing boundaries.

All eight public adapter defaults must remain formula blocks `{ value = 0 }`. Scalar zero defaults caused the confirmed AGOT nonzero-contribution regression. Adapters may override component slots and alliance calibration, but must not replace the core aggregate values or write persistent state.

`gui/interaction_marriage.gui` is the sole vanilla-path override. Changes require reviewing the frozen patch and native row callbacks, geometry and lifecycle cleanup together. The player snapshot is saveable state: preserve clearing behavior and correct character identity in projected rows. Do not change a frozen fingerprint without reviewing the corresponding code and upstream baseline.

## Layout and checks

- `mod/marriage_calc_assistant/`: developer source and the existing source README.
- `tests/mca/`: source checks, independent component/sort models, smoke evidence and historical release manifests.
- The sibling Parley repository's `tools/family/`: shared integration and frozen-GUI checks.

From this repository root, with Python 3 and PowerShell available:

```powershell
$mcaSource = (Resolve-Path './mod/marriage_calc_assistant').Path
$vanillaSource = 'D:/SteamLibrary/steamapps/common/Crusader Kings III/game'
$agotSource = 'D:/SteamLibrary/steamapps/workshop/content/1158310/2962333032'
& ./tests/mca/check_source.ps1 -McaRoot $mcaSource -GameRoot $vanillaSource
python ./tests/mca/test_genetics.py --mod $mcaSource --game $vanillaSource --agot $agotSource
python ./tests/mca/test_potential.py --mod $mcaSource
& ./tests/mca/test_sort_math.ps1
```

Inspect each result and exit code. For a family integration change, run the shared gate and frozen check with explicit Parley, MCA, adapter, vanilla and AGOT roots; see the sibling Parley `dev.md` for commands. The adapter test must receive this current MCA source explicitly.

Source checks protect the **18-file developer inventory**, including `mod/marriage_calc_assistant/README.md`. The document-free game package has a separate **17-file inventory**. Keep historical manifests unchanged and check the generated package with the release tooling in Parley's `tools/release/`; do not remove README from the source checker simply to accept a game package.

The developer source is edited here; `game` is generated; the Steam `workshop` download is compared with the uploaded package. Publication preparation includes a new focused smoke of the projected family package. The previous development tests and recorded smoke remain evidence for their exact builds and are not a certification of newly transformed package content.

The exact `2026-09-30-game-rc2` family package passed a focused combined smoke on CK3 1.19.0.6 with AGOT 0.5.2.1. MCA's candidate row and native tooltip were observed in a fresh English campaign: Ser Ronald Tinpenny displayed 24 = 6 skill + 18 age-based potential. This did not repeat the closed sorting, selection or dragonrider cases. The sibling Parley repository's `docs/RC2-SMOKE.md` records the complete scope and log caveats, including startup references to removed developer rules and three unattributed animation warnings. No new family-namespace errors appeared during the short run; whole-game clean logs and Workshop delivery are not claimed.

## Pull requests

Preserve UTF-8/BOM policy, LF endings, the complete nine-language key/token sets and the private `tnt_ma_sort_` namespace. A scoring change needs meaningful expected-value cases; a GUI/sorting change needs relevant lifecycle/selection evidence. Explain designer weights as comparison points, not acceptance, inheritance or offspring probabilities.

Include the problem, resulting behavior, tests run and remaining coverage. Do not commit saves, logs, local launcher descriptors, generated packages or Workshop downloads. Keep large historical research in the local backup archive; maintain concise current developer documentation here.

## Release-chain journals

[The dev-to-game journal](docs/releases/HISTORY.md), backed by `docs/releases/history.json`, records the current committed runtime associated with each verified game build. This is an association checked when recorded, not a claim about the original build commit or date.

Use the sibling Parley repository's `tools/release/release_journal.py`; its release README documents `init`, `status` and `record`. Separate Steam, Paradox, Nexus and GitHub histories live at the release workspace's `game/_history/<build>/<mod>/<platform>/`, outside immutable game payloads and upload archives. Each history has JSON evidence and a readable `HISTORY.md`.

Runtime hashes determine dev/game drift; GitHub's published revision is tracked separately so documentation-only commits do not invalidate game bytes. `UPLOADED` and `VERIFIED` require a publication URL, artifact identity and evidence. An upload is not download verification.

RC3 retains the CK3 1.19.0.6 / AGOT 0.5.2.1 evidence scope. CK3 1.20 compatibility remains unverified; the release workspace's `release-workflow.json` manages the publication hold while that review is pending.

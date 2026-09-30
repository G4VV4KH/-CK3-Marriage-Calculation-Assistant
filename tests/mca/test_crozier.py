"""CK3 1.20 source-driven arranger and inherited-row regressions.

Evaluates the actual narrow script authorization predicates. This models
scope identity and snapshot state; native callback timing still needs CK3.
"""
import argparse
from dataclasses import dataclass, field
from pathlib import Path
import re
import unittest

from test_potential import definitions


REPO = Path(__file__).resolve().parents[2]
PARSER = argparse.ArgumentParser()
PARSER.add_argument("--mod", type=Path, default=REPO / "mod/marriage_calc_assistant")
PARSER.add_argument("--game", type=Path, default=Path(
    "D:/SteamLibrary/steamapps/common/Crusader Kings III/game"))
CONFIG, UNIT_ARGS = PARSER.parse_known_args()


def only(nodes, name):
    result = [value for key, op, value in nodes if key == name and op == "="]
    if len(result) != 1:
        raise AssertionError(f"Expected one {name}, found {len(result)}")
    return result[0]


@dataclass(eq=False)
class Character:
    variables: dict = field(default_factory=dict)
    is_ai: bool = False


def evaluate(nodes, current, scopes):
    """Fail on unknown predicates instead of ignoring unevaluated branches."""
    def value(atom):
        if atom == "this":
            return current
        if atom.startswith("scope:"):
            return scopes.get(atom[6:])
        if atom.startswith("var:"):
            return current.variables.get(atom[4:])
        if re.fullmatch(r"-?\d+", atom):
            return int(atom)
        raise ValueError(f"Unsupported predicate value {atom!r}")

    results = []
    for key, op, body in nodes:
        if key in ("OR", "AND", "NOT"):
            branches = [evaluate([entry], current, scopes) for entry in body]
            result = any(branches) if key == "OR" else all(branches)
            results.append(not result if key == "NOT" else result)
        elif key == "exists":
            results.append(value(body) is not None)
        elif key == "has_variable":
            results.append(body in current.variables)
        elif key == "is_ai":
            results.append(current.is_ai == (body == "yes"))
        elif isinstance(body, list):
            target = value(key)
            results.append(target is not None and evaluate(body, target, scopes))
        else:
            left, right = value(key), value(body)
            if op == "=":
                results.append(left == right)
            elif op in (">", "<"):
                results.append(left is not None and right is not None and
                               (left > right if op == ">" else left < right))
            else:
                raise ValueError(f"Unsupported predicate operator {op!r}")
    return all(results)


def gui_block(text, opening):
    """Brace-match one GUI block, respecting comments and quoted expressions."""
    matches = list(re.finditer(opening, text))
    if len(matches) != 1:
        raise AssertionError(f"Expected one GUI block {opening}, found {len(matches)}")
    start = text.index("{", matches[0].start())
    depth, quoted, comment = 0, False, False
    for index in range(start, len(text)):
        ch = text[index]
        if comment:
            comment = ch != "\n"
            continue
        if ch == '"':
            quoted = not quoted
        elif not quoted:
            if ch == "#":
                comment = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return text[start:index + 1]
    raise AssertionError("Unclosed GUI block")


SORT_STATE_CALLBACKS = {
    "_hide": "clear",
    "tnt_ma_sort_capture_p_active": "collect",
    "tnt_ma_sort_capture_p_idle": None,
    "tnt_ma_sort_capture_r_active": "collect",
    "tnt_ma_sort_capture_r_idle": None,
    "tnt_ma_sort_invalidate": "clear",
    "tnt_ma_sort_complete": "finalize",
    "tnt_ma_sort_controller_idle": None,
    "tnt_ma_sort_watch_score_invalid": "clear",
    "tnt_ma_sort_watch_score_idle": None,
    "tnt_ma_sort_watch_identity_invalid": "clear",
    "tnt_ma_sort_watch_identity_idle": None,
}


def require_sort_state_properties(gui):
    """Callback states still execute, but must carry a harmless native property."""
    owner = gui_block(gui, r'vbox_character_list\s*=\s*\{')
    names = re.findall(r'\bstate\s*=\s*\{\s*name\s*=\s*("[^"]+"|\w+)', owner)
    if {name.strip('"') for name in names} != set(SORT_STATE_CALLBACKS):
        raise AssertionError("Sorter state inventory changed")
    for name, callback in SORT_STATE_CALLBACKS.items():
        quoted = '_hide' if name == '_hide' else '"' + name + '"'
        body = gui_block(owner, r'state\s*=\s*\{\s*name\s*=\s*' + re.escape(quoted))
        fields = re.findall(r'^\s*(\w+)\s*=\s*(.*?)\s*$', body, re.MULTILINE)
        keys = [key for key, value in fields]
        expected = {"name", "scale"}
        if name != "_hide":
            expected.add("trigger_when")
        if callback:
            expected.add("on_start")
        if len(keys) != len(expected) or set(keys) != expected:
            raise AssertionError(f"{name}: unexpected state properties/callbacks {keys}")
        values = dict(fields)
        if values["scale"] != "1":
            raise AssertionError(f"{name}: requires identity scale = 1")
        if callback and "GetScriptedGui('tnt_ma_sort_" + callback + "').Execute" not in values["on_start"]:
            raise AssertionError(f"{name}: state callback changed")


class CrozierContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sg = (CONFIG.mod / "common/scripted_guis/tnt_ma_sort.txt").read_text(
            encoding="utf-8-sig")
        cls.blocks = definitions(re.sub(r"saved_scopes\s*=\s*\{[^}]*\}", "", sg))
        start = only(cls.blocks["tnt_ma_sort_start"], "effect")
        cls.start_gate = next(only(body, "limit") for key, op, body in start
                              if key == "if" and any(
                                  k == "exists" and v == "scope:tnt_ma_sort_n"
                                  for k, o, v in only(body, "limit")))
        cls.context_gate = only(cls.blocks["tnt_ma_sort_context_valid"], "is_valid")
        cls.collect_gate = only(only(only(
            cls.blocks["tnt_ma_sort_collect"], "effect"), "if"), "limit")
        cls.gui = (CONFIG.mod / "gui/interaction_marriage.gui").read_text()
        cls.row = (CONFIG.mod / "gui/tnt_ma_character_list_item.gui").read_text()

    def scenario(self, state=1):
        owner = Character({"tnt_ma_sort_" + key: value for key, value in {
            "state": state, "expected": 2, "received": 0,
            "side": 1, "matrilineal": 0, "day": 100,
        }.items()})
        scopes = {"actor": owner, "tnt_ma_sort_arranger": owner,
                  "tnt_ma_sort_n": 2, "tnt_ma_sort_side": 1,
                  "tnt_ma_sort_matrilineal": 0, "tnt_ma_sort_day": 100}
        return owner, scopes

    def test_direct_player_can_start_capture_and_validate(self):
        owner, scopes = self.scenario()
        for gate in (self.start_gate, self.context_gate, self.collect_gate):
            self.assertTrue(evaluate(gate, owner, scopes))

    def test_puppet_and_missing_arranger_cannot_start_capture_or_validate(self):
        owner, scopes = self.scenario()
        for arranger in (Character(), None):
            scopes["tnt_ma_sort_arranger"] = arranger
            for gate in (self.start_gate, self.context_gate, self.collect_gate):
                self.assertFalse(evaluate(gate, owner, scopes))

    def test_same_numeric_state_does_not_confuse_character_identity(self):
        owner, scopes = self.scenario()
        scopes["tnt_ma_sort_arranger"] = Character(dict(owner.variables))
        self.assertFalse(evaluate(self.collect_gate, owner, scopes))
        self.assertFalse(evaluate(self.context_gate, owner, scopes))

    def test_ready_snapshot_invalidates_when_arranger_changes(self):
        owner, scopes = self.scenario(state=2)
        self.assertTrue(evaluate(self.context_gate, owner, scopes))
        scopes["tnt_ma_sort_arranger"] = Character()
        self.assertFalse(evaluate(self.context_gate, owner, scopes))
        controller = gui_block(self.gui, r'state\s*=\s*\{\s*name\s*=\s*"tnt_ma_sort_invalidate"')
        self.assertIn("Not( GetScriptedGui('tnt_ma_sort_context_valid').IsValid", controller)
        self.assertIn("GetScriptedGui('tnt_ma_sort_clear').Execute", controller)
        self.assertIn("GetPuppetOrActor.MakeScope", controller)

    def test_late_callbacks_never_collect_after_clear_ready_or_failure(self):
        for state in (0, 2, 3):
            owner, scopes = self.scenario(state)
            self.assertFalse(evaluate(self.collect_gate, owner, scopes))

    def test_arranger_guard_reaches_every_context_call_and_four_score_owners(self):
        packets = re.findall(r'[^\n]*GetScriptedGui\(\'tnt_ma_sort_(?:start|collect|context_valid)\'\)[^\n]*', self.gui)
        self.assertEqual(len(packets), 7)  # controller idle has two context calls
        self.assertEqual(self.gui.count(".AddScope('tnt_ma_sort_arranger', CharacterInteractionConfirmationWindow.GetPuppetOrActor.MakeScope)"), 8)
        gate = "And( ObjectsEqual( CharacterInteractionConfirmationWindow.GetActor, GetPlayer ), ObjectsEqual( CharacterInteractionConfirmationWindow.GetPuppetOrActor, GetPlayer ) )"
        for name in ("p", "p_alliance", "r", "r_alliance"):
            row = gui_block(self.row, r'text_single\s*=\s*\{\s*name\s*=\s*"tnt_ma_grade_' + name + '"')
            self.assertIn(gate, row)
        self.assertIn(gate, self.gui)

    def test_upstream_portrait_and_inherited_row_callbacks(self):
        upstream = (CONFIG.game / "gui/interaction_marriage.gui").read_text(encoding="utf-8-sig")
        for text in (upstream, self.gui):
            portrait = gui_block(text, r'blockoverride\s+"left_small_portrait"\s*\{')
            self.assertIn('[CharacterInteractionConfirmationWindow.GetPuppetOrActor]', portrait)
        lists = (CONFIG.game / "gui/shared/lists.gui").read_text(encoding="utf-8-sig")
        row = gui_block(lists, r'type\s+widget_character_list_item\s*=\s*widget\s*\{')
        for seam in ('[CharacterListItem.GetCharacter]', "[CharacterListItem.OnClick('character')]",
                     '[CharacterListItem.IsSelectable]', '[CharacterListItem.GetUnselectableReason]',
                     'block "character_relation"', 'Character.GetRelationToString( GetPlayer )',
                     '[CharacterListItem.GetSkillItems]', 'min_width = 320', 'max_width = 320'):
            self.assertIn(seam, row)
        self.assertNotIn('CharacterListItem.OnClick', self.row)
        self.assertNotIn('CharacterListItem.IsSelectable', self.row)

    def test_marriage_eligibility_and_alliance_metadata_stay_native(self):
        self.assertFalse((CONFIG.mod / "common/character_interactions").exists())
        self.assertFalse((CONFIG.mod / "common/scripted_triggers").exists())
        for path in (CONFIG.mod / "common/script_values").glob('*.txt'):
            code = re.sub(r'#[^\n]*', '', path.read_text(encoding="utf-8-sig"))
            self.assertNotRegex(code, r'\b(?:has_doctrine|rite_has_doctrine|can_marry_character_trigger|is_same_faith)\b')
        self.assertEqual(self.row.count('DataModelHasItems( CharacterListItem.GetOtherCharacterItems )'), 4)
        for name in ('p', 'r'):
            capture = gui_block(self.gui, r'state\s*=\s*\{\s*name\s*=\s*"tnt_ma_sort_capture_' + name + '_active"')
            self.assertIn(".AddScope('tnt_ma_sort_alliance', MakeScopeValue( Select_CFixedPoint( DataModelHasItems( CharacterListItem.GetOtherCharacterItems )", capture)

    def test_callback_states_have_only_native_identity_scale(self):
        require_sort_state_properties(self.gui)
        # Native demonstrates a valid state with only a name and identity scale.
        native = (CONFIG.game / "gui/hud_notification_templates.gui").read_text(encoding="utf-8-sig")
        self.assertRegex(native, r'state\s*=\s*\{\s*name\s*=\s*_mouse_release\s+scale\s*=\s*1\s*\}')

    def test_empty_or_visual_state_mutations_are_rejected(self):
        for name in ("tnt_ma_sort_capture_p_active", "tnt_ma_sort_watch_identity_idle"):
            with self.subTest(name=name):
                block = gui_block(self.gui, r'state\s*=\s*\{\s*name\s*=\s*"' + name + '"')
                for replacement in ("", "scale = 0", "alpha = 1", "duration = 0"):
                    changed = self.gui.replace(block, block.replace("scale = 1", replacement), 1)
                    with self.assertRaises(AssertionError):
                        require_sort_state_properties(changed)


if __name__ == "__main__":
    unittest.main(argv=[__file__] + UNIT_ARGS, verbosity=2)

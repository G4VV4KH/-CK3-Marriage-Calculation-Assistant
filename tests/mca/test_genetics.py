"""Evaluate the actual narrow CK3 genetics script; this is not an engine test.

The parser deliberately accepts only the grammar used by this pure component.
Unknown grammar fails instead of silently being skipped. Structural checks pin
the six consumers, sorter reuse, localization and the preserved genetics body.
Other candidate components are independently tested by test_potential.py.
"""
import argparse
import hashlib
import re
from itertools import product
from pathlib import Path
import unittest


REPO = Path(__file__).resolve().parents[2]
ARGS = argparse.ArgumentParser()
ARGS.add_argument("--mod", type=Path, default=REPO / "mod/marriage_calc_assistant")
ARGS.add_argument("--game", type=Path, default=Path(
    "D:/SteamLibrary/steamapps/common/Crusader Kings III/game"))
ARGS.add_argument("--agot", type=Path, default=Path(
    "D:/SteamLibrary/steamapps/workshop/content/1158310/2962333032"))
CONFIG, UNIT_ARGS = ARGS.parse_known_args()
VALUE_NAME = "tnt_ma_genetic_value"
LOC_KEY = "tnt_ma_grade_genetic"
LANGS = ("english", "french", "german", "japanese", "korean", "polish",
         "russian", "simp_chinese", "spanish")
FAMILIES = ("intellect", "beauty", "physique")
WEIGHTS = {
    f"{family}_{sign}_{tier}": tier * direction
    for family, (sign, direction), tier in product(
        FAMILIES, (("good", 10), ("bad", -10)), (1, 2, 3))
}
WEIGHTS.update(pure_blooded=10, fecund=10, inbred=-50, bleeder=-30,
               infertile=-50, spindly=-10, wheezing=-10, clubfooted=-10,
               hunchbacked=-10, lisping=-5, stuttering=-5)


def without_comments(text):
    return re.sub(r"#[^\n]*", "", text)


def block(text, name):
    text = without_comments(text)
    matches = list(re.finditer(r"(?m)^" + re.escape(name) + r"\s*=\s*\{", text))
    if len(matches) != 1:
        raise ValueError(f"Expected one definition of {name}, got {len(matches)}")
    start = matches[0].end()
    depth = 1
    for pos in range(start, len(text)):
        depth += (text[pos] == "{") - (text[pos] == "}")
        if depth == 0:
            return text[start:pos]
    raise ValueError(f"Unclosed definition: {name}")


RULE = re.compile(
    r"\s*(?P<kind>if|else_if)\s*=\s*\{\s*limit\s*=\s*\{\s*"
    r"has_trait\s*=\s*(?P<trait>[a-z0-9_]+)\s*\}\s*"
    r"add\s*=\s*(?P<delta>-?\d+)\s*\}")


def parse_component(body):
    start = re.match(r"\s*value\s*=\s*0\b", body)
    if start is None:
        raise ValueError("Genetics must start at zero")
    pos, rules = start.end(), []
    while body[pos:].strip():
        match = RULE.match(body, pos)
        if match is None:
            raise ValueError(f"Unsupported component grammar: {body[pos:pos + 80]!r}")
        if match["kind"] == "else_if" and not rules:
            raise ValueError("Orphan else_if")
        rules.append((match["kind"], match["trait"], int(match["delta"])))
        pos = match.end()
    return rules


def evaluate(rules, traits):
    present, value, taken = set(traits), 0, False
    for kind, trait, delta in rules:
        if kind == "if":
            taken = False
        if not taken and trait in present:
            value += delta
            taken = True
    return value


class GeneticsContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.grade_bytes = (CONFIG.mod / "common/script_values/tnt_ma_52_grade.txt").read_bytes()
        cls.grade = cls.grade_bytes.decode("utf-8")
        cls.rules = parse_component(block(cls.grade, VALUE_NAME))
        cls.capture = (CONFIG.mod / "common/script_values/tnt_ma_sort_capture.txt").read_text(
            encoding="utf-8-sig")

    def score(self, *traits):
        return evaluate(self.rules, traits)

    def test_explicit_allowlist_and_weights(self):
        self.assertEqual(len(self.rules), len(WEIGHTS))
        self.assertEqual({trait: weight for _, trait, weight in self.rules}, WEIGHTS)
        self.assertEqual(self.score(), 0)
        for trait, expected in WEIGHTS.items():
            with self.subTest(trait=trait):
                self.assertEqual(self.score(trait), expected)

    def test_monotonic_tiers_with_each_shared_marriage_baseline(self):
        for family, baseline in product(FAMILIES, (-900, -50, 0, 121, 125, 128, 1000)):
            traits = [f"{family}_bad_{n}" for n in (3, 2, 1)]
            traits += [None] + [f"{family}_good_{n}" for n in (1, 2, 3)]
            scores = [baseline + self.score(*([trait] if trait else [])) for trait in traits]
            with self.subTest(family=family, baseline=baseline):
                self.assertTrue(all(a < b for a, b in zip(scores, scores[1:])))

    def test_independent_families_add_all_343_valid_combinations(self):
        levels = range(-3, 4)
        for chosen in product(levels, repeat=3):
            traits = [f"{family}_{'good' if n > 0 else 'bad'}_{abs(n)}"
                      for family, n in zip(FAMILIES, chosen) if n]
            with self.subTest(levels=chosen):
                self.assertEqual(self.score(*traits), 10 * sum(chosen))

    def test_malformed_multitier_state_never_counts_lower_levels_twice(self):
        for family, sign in product(FAMILIES, ("good", "bad")):
            expected = 30 if sign == "good" else -30
            self.assertEqual(self.score(*(f"{family}_{sign}_{n}" for n in (1, 2, 3))), expected)

    def test_manual_inheritance_and_separate_conditions_are_additive(self):
        self.assertEqual(self.score("pure_blooded", "fecund"), 20)
        self.assertEqual(self.score("inbred", "bleeder", "intellect_good_1"), -70)
        self.assertEqual(self.score("physique_good_3", "infertile"), -20)
        self.assertEqual(self.score("lisping", "clubfooted", "beauty_good_2"), 5)

    def test_excluded_qualities_do_not_leak_into_genetics(self):
        excluded = ("strong", "shrewd", "weak", "dull", "giant", "dwarf", "albino",
                    "scaly", "depressed_1", "depressed_genetic", "lunatic_1", "lunatic_genetic",
                    "possessed_1", "possessed_genetic", "dragonrider", "dragonblood")
        self.assertEqual(self.score(*excluded), 0)

    def test_one_direct_positive_addend_in_all_six_consumers(self):
        addend = r"add\s*=\s*\{\s*value\s*=\s*tnt_ma_genetic_value\s+desc\s*=\s*tnt_ma_grade_genetic\s*\}"
        for side, suffix in product(("p", "r"), ("raw_value", "value", "alliance_value")):
            name = f"tnt_ma_grade_{side}_{suffix}"
            body = block(self.grade, name)
            with self.subTest(consumer=name):
                self.assertEqual(len(re.findall(addend, body)), 1)
                self.assertEqual(len(re.findall(r"\btnt_ma_genetic_value\b", body)), 1)
        self.assertEqual(len(re.findall(addend, self.grade)), 6)

    def test_sort_uses_the_same_displayed_values_and_candidate_root_legacy(self):
        for side in ("p", "r", "p_alliance", "r_alliance"):
            body = block(self.capture, f"tnt_ma_sort_{side}_capture_value")
            self.assertEqual(len(re.findall(r"value\s*=\s*tnt_ma_grade_" + side + r"_value\b", body)), 1)
            self.assertNotIn(VALUE_NAME, body)
        legacy = block(self.grade, "tnt_spouse_grade_value")
        for side in ("p", "r"):
            self.assertRegex(legacy, r"scope:tnt_sp_one\s*=\s*\{\s*add\s*=\s*tnt_ma_grade_" + side + r"_raw_value\s*\}")

    def test_genetics_body_preserves_the_approved_23_contract(self):
        # Freeze only the actual genetics instructions, not unrelated legacy
        # components that 3.0 intentionally retires. Comments/format may change.
        normalized = re.sub(r"\s+", "", block(self.grade, VALUE_NAME))
        self.assertEqual(hashlib.sha256(normalized.encode("utf-8")).hexdigest().upper(),
                         "ADDB833A7EAD74019960C4BDE0DA939F99B0E4A85EA015C93D76C66FDC2A14A1")

    def test_new_localization_exists_once_in_all_nine_languages(self):
        for lang in LANGS:
            text = (CONFIG.mod / f"localization/{lang}/tnt_ma_l_{lang}.yml").read_text(encoding="utf-8-sig")
            with self.subTest(language=lang):
                self.assertEqual(len(re.findall(r"(?m)^ " + LOC_KEY + r':0 "[^"\n]+"$', text)), 1)

    def test_referenced_traits_exist_and_are_inheritable_in_both_installed_games(self):
        for root in (CONFIG.game, CONFIG.agot):
            text = (root / "common/traits/00_traits.txt").read_text(encoding="utf-8-sig")
            for trait in WEIGHTS:
                with self.subTest(game=str(root), trait=trait):
                    body = block(text, trait)
                    self.assertRegex(body, r"\bgenetic\s*=\s*yes\b|\binherit_chance\s*=\s*[1-9][0-9]*\b")

    def test_unknown_component_grammar_is_rejected(self):
        for invalid in ("value = 10", "value = 0\nadd = hidden_dragonblood", "value = 0\nset_variable = foo"):
            with self.assertRaises(ValueError):
                parse_component(invalid)


if __name__ == "__main__":
    unittest.main(argv=[__file__] + UNIT_ARGS)

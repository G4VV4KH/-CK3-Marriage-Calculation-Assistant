"""Evaluate MCA's actual 3.0 potential components with a strict script subset.

This is an independent model of the supplied script, not a CK3 runtime/parser
test or a forecast of children, inheritance, council eligibility or war gains.
Unknown syntax and unknown trigger/value names fail even in an untaken branch.
"""
import argparse
from dataclasses import dataclass, field
from decimal import Decimal, ROUND_FLOOR, ROUND_HALF_UP
from pathlib import Path
import re
import unittest


REPO = Path(__file__).resolve().parents[2]
ARGS = argparse.ArgumentParser()
ARGS.add_argument("--mod", type=Path, default=REPO / "mod/marriage_calc_assistant")
CONFIG, UNIT_ARGS = ARGS.parse_known_args()
SKILLS = ("diplomacy", "martial", "stewardship", "intrigue", "learning")
COMPONENTS = ("skill", "age", "dynasty", "claim")
TIERS = {"tier_barony": 1, "tier_county": 2, "tier_duchy": 3,
         "tier_kingdom": 4, "tier_empire": 5, "tier_hegemony": 6}
TOKEN = re.compile(r"\s*(\?=|!=|>=|<=|[{}=<>]|-?\d+(?:\.\d+)?|[A-Za-z_][\w:.|]*)")


def parse(text):
    """Parse assignments/comparisons, preserving order and duplicate keys."""
    text = re.sub(r"#[^\n]*", "", text).lstrip("\ufeff")
    tokens, pos = [], 0
    while text[pos:].strip():
        match = TOKEN.match(text, pos)
        if match is None:
            raise ValueError(f"Unsupported token at {text[pos:pos + 50]!r}")
        tokens.append(match[1])
        pos = match.end()
    index = 0

    def entries(nested=False):
        nonlocal index
        result = []
        while index < len(tokens):
            if tokens[index] == "}":
                if not nested:
                    raise ValueError("Unexpected closing brace")
                index += 1
                return result
            if index + 2 >= len(tokens):
                raise ValueError("Incomplete assignment")
            key, op, value = tokens[index:index + 3]
            if not re.fullmatch(r"[A-Za-z_][\w:.|]*", key):
                raise ValueError(f"Unsupported key {key!r}")
            if op not in ("=", "?=", "!=", ">", ">=", "<", "<="):
                raise ValueError(f"Unsupported operator {op!r}")
            index += 3
            if value == "{":
                value = entries(True)
            elif value in ("}", "=", "?=", "!=", ">", ">=", "<", "<="):
                raise ValueError("Missing right-hand side")
            result.append((key, op, value))
        if nested:
            raise ValueError("Unclosed block")
        return result

    return entries()


def definitions(text):
    result = {}
    for name, op, body in parse(text):
        if name in result or op != "=" or not isinstance(body, list):
            raise ValueError(f"Invalid/duplicate definition {name}")
        result[name] = body
    return result


@dataclass(frozen=True)
class Claim:
    tier: int
    pressed: bool = False
    explicit: bool = True


@dataclass
class Candidate:
    effective_age: int = 25
    age: int = 25
    is_female: bool = False
    is_incapable: bool = False
    traits: set = field(default_factory=set)
    skills: dict = field(default_factory=lambda: dict.fromkeys(SKILLS, 0))
    dynasty_level: int | None = None
    claims: tuple = ()
    unrelated: dict = field(default_factory=dict)


class Evaluator:
    """Only the explicit pure arithmetic and candidate triggers used by MCA."""
    arithmetic = {"value", "add", "subtract", "multiply", "divide", "min", "max"}
    rounding = {"floor", "round", "ceiling"}
    scalars = set(SKILLS) | {"effective_age", "dynasty_prestige_level", "dynasty.dynasty_prestige_level"}

    def __init__(self, blocks):
        self.blocks = blocks

    @staticmethod
    def number(value):
        return isinstance(value, str) and re.fullmatch(r"-?\d+(?:\.\d+)?", value)

    def validate_scalar(self, value):
        if isinstance(value, list):
            self.validate_value(value)
        elif not (self.number(value) or value in self.scalars):
            raise ValueError(f"Unknown numeric value {value!r}")

    def validate_value(self, body):
        chain = False
        for key, op, value in body:
            if op != "=":
                raise ValueError(f"Unsupported value operator {op}")
            if key in self.arithmetic:
                self.validate_scalar(value)
                chain = False
            elif key in self.rounding:
                if value != "yes":
                    raise ValueError("Only affirmative rounding is supported")
                chain = False
            elif key in ("if", "else_if", "else"):
                if not isinstance(value, list) or (key != "if" and not chain):
                    raise ValueError(f"Invalid conditional {key}")
                limits = [v for k, o, v in value if k == "limit" and o == "="]
                if len(limits) != (key != "else"):
                    raise ValueError("Conditional must have exactly its expected limit")
                if limits:
                    self.validate_trigger(limits[0])
                self.validate_value([entry for entry in value if entry[0] != "limit"])
                chain = key != "else"
            elif key == "dynasty":
                if not isinstance(value, list):
                    raise ValueError("Expected dynasty scope block")
                self.validate_value(value)
                chain = False
            elif key == "every_claim":
                if not isinstance(value, list):
                    raise ValueError("Expected claim iterator block")
                for filter_name in ("explicit", "pressed"):
                    filters = [(o, v) for k, o, v in value if k == filter_name]
                    if len(filters) != 1 or filters[0][0] != "=" or filters[0][1] not in ("yes", "no"):
                        raise ValueError(f"Expected one {filter_name} claim filter")
                self.validate_value([entry for entry in value if entry[0] not in ("explicit", "pressed")])
                chain = False
            else:
                raise ValueError(f"Unknown value instruction {key!r}")

    def validate_trigger(self, body):
        if not isinstance(body, list):
            raise ValueError("Expected trigger block")
        for key, op, value in body:
            if key in ("AND", "OR", "NOT", "NOR", "any_claim"):
                if op != "=":
                    raise ValueError("Unsupported logical operator")
                self.validate_trigger(value)
            elif key in ("is_female", "is_incapable", "has_dynasty"):
                if op != "=" or value not in ("yes", "no"):
                    raise ValueError("Unsupported boolean")
            elif key == "has_trait":
                if op != "=" or not re.fullmatch(r"[a-z0-9_]+", str(value)):
                    raise ValueError("Unsupported trait test")
            elif key == "exists":
                if op != "=" or value != "dynasty":
                    raise ValueError("Only candidate dynasty existence is allowed")
            elif key in ("effective_age", "tier"):
                if op not in ("=", "!=", ">", ">=", "<", "<="):
                    raise ValueError("Unsupported numeric comparison")
                if not self.number(value) and not (key == "tier" and value in TIERS):
                    raise ValueError("Unsupported numeric trigger RHS")
            else:
                raise ValueError(f"Unknown trigger {key!r}")

    def scalar(self, value, candidate, current=None):
        if isinstance(value, list):
            return self.run(value, candidate, current)
        if self.number(value):
            return Decimal(value)
        if value in candidate.skills:
            return Decimal(candidate.skills[value])
        if value == "effective_age":
            return Decimal(candidate.effective_age)
        if value == "dynasty_prestige_level":
            if current != "dynasty" or candidate.dynasty_level is None:
                raise ValueError("Dynasty prestige used outside valid dynasty scope")
            return Decimal(candidate.dynasty_level)
        if value == "dynasty.dynasty_prestige_level":
            if candidate.dynasty_level is None:
                raise ValueError("Dynasty prestige used on a lowborn candidate")
            return Decimal(candidate.dynasty_level)
        if value in self.blocks:
            return self.run(self.blocks[value], candidate, current)
        raise ValueError(f"Unknown scalar {value!r}")

    def trigger(self, body, candidate, current=None):
        outcomes = []
        for key, op, value in body:
            if key in ("AND", "OR", "NOT", "NOR"):
                children = [self.trigger([entry], candidate, current) for entry in value]
                outcomes.append({"AND": all(children), "OR": any(children),
                                 "NOT": not all(children), "NOR": not any(children)}[key])
            elif key == "any_claim":
                outcomes.append(any(self.trigger(value, candidate, claim) for claim in candidate.claims))
            elif key in ("is_female", "is_incapable"):
                outcomes.append(getattr(candidate, key) == (value == "yes"))
            elif key == "has_dynasty":
                outcomes.append((candidate.dynasty_level is not None) == (value == "yes"))
            elif key == "has_trait":
                outcomes.append(value in candidate.traits)
            elif key == "exists":
                outcomes.append(candidate.dynasty_level is not None)
            elif key in ("effective_age", "tier"):
                left = candidate.effective_age if key == "effective_age" else current.tier
                right = TIERS[value] if value in TIERS else Decimal(value)
                outcomes.append({"=": left == right, "!=": left != right, ">": left > right,
                                 ">=": left >= right, "<": left < right, "<=": left <= right}[op])
            else:
                raise ValueError(f"Unknown trigger {key!r}")
        return all(outcomes)

    def run(self, body, candidate, current=None, initial=Decimal(0)):
        result, taken = initial, False
        for key, op, value in body:
            if key in self.arithmetic:
                n = self.scalar(value, candidate, current)
                if key == "value": result = n
                elif key == "add": result += n
                elif key == "subtract": result -= n
                elif key == "multiply": result *= n
                elif key == "divide": result /= n
                elif key == "min": result = max(result, n)  # CK3 lower clamp
                elif key == "max": result = min(result, n)  # CK3 upper clamp
            elif key in self.rounding:
                if key == "floor": result = result.to_integral_value(rounding=ROUND_FLOOR)
                elif key == "round": result = result.to_integral_value(rounding=ROUND_HALF_UP)
                else: result = -(-result).to_integral_value(rounding=ROUND_FLOOR)
            elif key in ("if", "else_if", "else"):
                if key == "if": taken = False
                limits = [v for k, o, v in value if k == "limit"]
                if not taken and (not limits or self.trigger(limits[0], candidate, current)):
                    result = self.run([entry for entry in value if entry[0] != "limit"],
                                      candidate, current, result)
                    taken = True
            elif key == "dynasty":
                if candidate.dynasty_level is not None:
                    result = self.run(value, candidate, "dynasty", result)
            elif key == "every_claim":
                filters = {k: v == "yes" for k, o, v in value if k in ("explicit", "pressed")}
                instructions = [entry for entry in value if entry[0] not in filters]
                for claim in candidate.claims:
                    if all(getattr(claim, key) == expected for key, expected in filters.items()):
                        result = self.run(instructions, candidate, claim, result)
            else:
                raise ValueError(f"Unknown value instruction {key!r}")
        return result

    def score(self, name, candidate):
        body = self.blocks[f"tnt_ma_{name}_value"]
        self.validate_value(body)
        return self.run(body, candidate)


class PotentialContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = (CONFIG.mod / "common/script_values/tnt_ma_52_grade.txt").read_text(encoding="utf-8-sig")
        cls.blocks = definitions(cls.text)
        cls.evaluator = Evaluator(cls.blocks)
        for component in COMPONENTS:
            cls.evaluator.validate_value(cls.blocks[f"tnt_ma_{component}_value"])

    def score(self, component, **kwargs):
        return self.evaluator.score(component, Candidate(**kwargs))

    def test_skill_floors_minimum_one_per_stat_and_cap(self):
        for skill in (0, 1, 4, 5, 9, 10, 29, 30, 50, 100):
            with self.subTest(skill=skill):
                self.assertEqual(self.score("skill", skills=dict.fromkeys(SKILLS, skill)),
                                 min(30, 5 * max(1, skill // 5)))
        self.assertEqual(self.score("skill", skills=dict(zip(SKILLS, (4, 5, 9, 10, 49)))), 14)

    def test_skills_require_effective_adulthood_and_capacity(self):
        self.assertEqual(self.score("skill", effective_age=15, skills=dict.fromkeys(SKILLS, 100)), 0)
        self.assertEqual(self.score("skill", effective_age=16, skills=dict.fromkeys(SKILLS, 10)), 10)
        self.assertEqual(self.score("skill", is_incapable=True, skills=dict.fromkeys(SKILLS, 100)), 0)

    def test_female_age_boundaries_with_and_without_fecund(self):
        expected = {0: 0, 15: 0, 16: 20, 25: 20, 26: 18, 30: 18,
                    31: 14, 35: 14, 36: 10, 40: 10, 41: 7, 45: 7,
                    46: 0, 50: 0, 51: 0, 100: 0}
        for age, points in expected.items():
            with self.subTest(age=age):
                self.assertEqual(self.score("age", effective_age=age, is_female=True), points)
                self.assertEqual(self.score("age", effective_age=age, is_female=True, traits={"fecund"}),
                                 2 if 46 <= age <= 50 else points)

    def test_male_age_boundaries(self):
        expected = {0: 0, 15: 0, 16: 20, 35: 20, 36: 18, 40: 18,
                    41: 16, 50: 16, 51: 14, 60: 14, 61: 12, 70: 12,
                    71: 10, 110: 10}
        for age, points in expected.items():
            with self.subTest(age=age):
                self.assertEqual(self.score("age", effective_age=age), points)

    def test_age_visible_blockers_and_no_hidden_fertility_input(self):
        for female in (False, True):
            self.assertEqual(self.score("age", is_female=female, is_incapable=True), 0)
            for trait in ("eunuch_1", "beardless_eunuch", "celibate"):
                with self.subTest(female=female, trait=trait):
                    self.assertEqual(self.score("age", is_female=female, traits={trait}), 0)
            # Infertile's hereditary penalty belongs to G; F is an age-only
            # opportunity index, not a claim that the candidate can conceive.
            self.assertEqual(self.score("age", is_female=female, traits={"infertile"}), 20)

    def test_effective_age_not_calendar_age_drives_both_age_and_skills(self):
        for component in ("age", "skill"):
            self.assertEqual(self.score(component, age=1000, effective_age=25),
                             self.score(component, age=25, effective_age=25))
            self.assertEqual(self.score(component, age=1000, effective_age=15), 0)

    def test_genetics_remain_separate_from_present_adult_utility(self):
        child = Candidate(effective_age=0, traits={"intellect_good_3"}, skills=dict.fromkeys(SKILLS, 5))
        self.assertEqual(self.evaluator.score("genetic", child), 30)
        self.assertEqual(self.evaluator.score("skill", child), 0)
        self.assertEqual(self.evaluator.score("age", child), 0)
        adult = Candidate(traits={"intellect_good_3"}, skills=dict.fromkeys(SKILLS, 15))
        self.assertEqual(self.evaluator.score("genetic", adult), 30)
        self.assertEqual(self.evaluator.score("skill", adult), 15)
        infertile = Candidate(traits={"infertile"})
        self.assertEqual(self.evaluator.score("genetic", infertile), -50)
        self.assertEqual(self.evaluator.score("age", infertile), 20)

    def test_dynasty_lowborn_and_all_levels_clamp(self):
        self.assertEqual(self.score("dynasty"), -5)
        for level in (-2, 0, 1, 2, 3, 5, 9, 10, 11, 100):
            with self.subTest(level=level):
                self.assertEqual(self.score("dynasty", dynasty_level=level), max(-5, min(45, (level - 1) * 5)))

    def test_claim_strength_tier_and_cap(self):
        self.assertEqual(self.score("claim"), 0)
        for tier, weight in ((1, 1), (2, 2), (3, 4), (4, 8), (5, 12), (6, 12)):
            for pressed in (False, True):
                with self.subTest(tier=tier, pressed=pressed):
                    self.assertEqual(self.score("claim", claims=(Claim(tier, pressed),)), weight * (2 if pressed else 1))

    def test_claims_choose_strongest_not_count_or_first(self):
        claims = (Claim(1), Claim(2, True), Claim(4, True), Claim(5))
        self.assertEqual(self.score("claim", claims=claims), 16)
        self.assertEqual(self.score("claim", claims=tuple(reversed(claims))), 16)
        self.assertEqual(self.score("claim", claims=claims * 100), 16)
        self.assertEqual(self.score("claim", claims=claims + (Claim(6, True),)), 24)

    def test_implicit_claims_never_contribute(self):
        implicit = (Claim(6, True, False), Claim(5, False, False))
        self.assertEqual(self.score("claim", claims=implicit), 0)
        self.assertEqual(self.score("claim", claims=implicit + (Claim(2),)), 2)

    def test_social_context_never_changes_shared_candidate_values(self):
        baseline = Candidate(skills=dict.fromkeys(SKILLS, 12), dynasty_level=4, claims=(Claim(2),))
        varied = Candidate(skills=dict.fromkeys(SKILLS, 12), dynasty_level=4, claims=(Claim(2),),
                           unrelated={"opinion": -100, "court": "different", "liege": "king",
                                      "inspiration": True, "lover": True, "family": True,
                                      "fertility": 0, "health": 0, "real_father": "secret"})
        for component in COMPONENTS:
            self.assertEqual(self.evaluator.score(component, baseline), self.evaluator.score(component, varied))

    def test_eight_legacy_components_are_exact_zero_stubs(self):
        for side in ("p", "r"):
            for n in range(1, 5):
                self.assertEqual(self.blocks[f"tnt_ma_sg_{side}_c{n}_value"], [("value", "=", "0")])

    def test_all_five_shared_components_appear_once_in_all_six_consumers(self):
        for side in ("p", "r"):
            for suffix in ("raw_value", "value", "alliance_value"):
                body = self.blocks[f"tnt_ma_grade_{side}_{suffix}"]
                serialized = repr(body)
                for name in (*COMPONENTS, "genetic"):
                    self.assertEqual(serialized.count(f"'tnt_ma_{name}_value'"), 1)
                    self.assertEqual(serialized.count(f"'tnt_ma_grade_{name}'"), 1)
                self.assertNotRegex(serialized, r"tnt_ma_sg_[pr]_c[1-4]_value")

    def test_negative_fixtures_reject_unknown_syntax_even_in_dead_branches(self):
        invalid = ("value = 0 set_variable = foo",
                   "value = hidden_fertility",
                   "value = tnt_ma_ally_worth_value",
                   "value = 0 if = { limit = { effective_age < 0 } add = secret_genes }",
                   "value = 0 if = { limit = { opinion > 10 } add = 5 }",
                   "value = 0 every_claim = { add = 5 }",
                   "value = 0 else_if = { limit = { is_female = yes } add = 5 }")
        for text in invalid:
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.evaluator.validate_value(parse(text))
        for text in ("value = {", "value = 0 }", "value = @hidden", "value ="):
            with self.subTest(text=text), self.assertRaises(ValueError):
                parse(text)


if __name__ == "__main__":
    unittest.main(argv=[__file__] + UNIT_ARGS)

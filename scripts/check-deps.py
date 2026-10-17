#!/usr/bin/env python3
"""Checks the target dependency rules of CLAUDE.md / DESIGN §4.10 on `swift package dump-package`
output (read from stdin): Core depends on no module or UI target; modules depend only on Core and
VoCoderUI (the demo module also on the fakes) and never on each other; only the executable and
test targets depend on modules; the fakes and test support stay out of real modules."""
import json
import sys

package = json.load(sys.stdin)
targets = {t["name"]: t for t in package["targets"]}


def deps(target):
    names = []
    for dep in target.get("dependencies", []):
        kind, value = next(iter(dep.items()))
        names.append(value[0])  # byName / target / product: first element is the name
    return set(names)


modules = {n for n, t in targets.items() if (t.get("path") or "").startswith("Sources/Modules/")}
allowed = {
    "VoCoderCore": {"TOMLDecoder"},
    "VoCoderUIBridge": {"CFTXUI"},
    "VoCoderUI": {"VoCoderCore", "VoCoderUIBridge"},
    "VoCoderVoice": {"VoCoderCore"},
    "VoCoderFakes": {"VoCoderCore"},
    "VoCoderTestSupport": {"VoCoderCore", "VoCoderFakes"},
    "VoCoderUITestSupport": {"VoCoderUI", "VoCoderUIBridge"},
}
for module in modules:
    allowed[module] = {"VoCoderCore", "VoCoderUI"} | ({"VoCoderFakes"} if module == "DemoModule" else set())

errors = []
for name, target in targets.items():
    if target["type"] in ("test", "executable"):
        continue
    if name not in allowed:
        if name != "CFTXUI":
            errors.append(f"{name}: no dependency rule (add one to scripts/check-deps.py)")
        continue
    extra = deps(target) - allowed[name]
    if extra:
        errors.append(f"{name} may not depend on {', '.join(sorted(extra))}")

if errors:
    print("dependency rules violated:", *errors, sep="\n  ", file=sys.stderr)
    sys.exit(1)
print(f"dependency rules ok ({len(modules)} modules)")

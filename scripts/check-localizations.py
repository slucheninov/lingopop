#!/usr/bin/env python3
"""Consistency check for App/Localizable.xcstrings.

Usage: check-localizations.py [path]   (default: App/Localizable.xcstrings)
Exit 0 = clean; exit 1 = one line per problem: KEY | lang | problem.
"""
import json
import re
import sys
from collections import Counter

LANGS = ("pl", "uk", "de")
SPEC_RE = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|%)")
TOKENS = ("…", "→", "⌘", "{{targetLanguage}}")


def signature(s):
    return Counter(SPEC_RE.findall(s)), s.count("\n"), tuple(s.count(t) for t in TOKENS)


def describe(sig):
    specs, nl, toks = sig
    parts = ["specs=%s" % (sorted(specs.elements()),), "newlines=%d" % nl]
    parts += ["%r=%d" % (t, n) for t, n in zip(TOKENS, toks)]
    return " ".join(parts)


def units(loc):
    """Yield (label, stringUnit) for a localization (plain or variations)."""
    if "stringUnit" in loc:
        yield "", loc["stringUnit"]
    def walk(node, path):
        for kind, cases in node.items():
            for case, body in cases.items():
                p = "%s%s.%s" % (path, kind, case)
                if "stringUnit" in body:
                    yield p, body["stringUnit"]
                if "variations" in body:
                    yield from walk(body["variations"], p + "/")
    if "variations" in loc:
        yield from walk(loc["variations"], "")


def main(argv):
    path = argv[1] if len(argv) > 1 else "App/Localizable.xcstrings"
    with open(path, encoding="utf-8") as f:
        catalog = json.load(f)
    problems = []
    for key, entry in catalog.get("strings", {}).items():
        if entry.get("shouldTranslate") is False:
            continue
        locs = entry.get("localizations", {})
        ref = key
        for label, u in units(locs["en"]) if "en" in locs else ():
            if label == "":
                ref = u.get("value", key)
        ref_sig = signature(ref)
        for lang in LANGS:
            loc = locs.get(lang)
            if loc is None:
                problems.append((key, lang, "missing translation"))
                continue
            found = False
            for label, u in units(loc):
                found = True
                tag = lang + (" [%s]" % label if label else "")
                if u.get("state") != "translated":
                    problems.append((key, tag, "state is %r, expected 'translated'" % u.get("state")))
                sig = signature(u.get("value", ""))
                if sig != ref_sig:
                    problems.append((key, tag, "mismatch: expected {%s} got {%s}" % (describe(ref_sig), describe(sig))))
            if not found:
                problems.append((key, lang, "no stringUnit"))
        for lang, loc in locs.items():
            if lang in LANGS or lang == "en":
                continue
            for label, u in units(loc):
                if signature(u.get("value", "")) != ref_sig:
                    problems.append((key, lang, "mismatch against source"))
    for key, lang, msg in problems:
        print("%s | %s | %s" % (key.replace("\n", "\\n"), lang, msg))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

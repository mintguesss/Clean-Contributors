"""Checks the git-filter-repo message callback published in the docs.

The callback is extracted from strip-coauthors/SKILL.md and README.md, so the
test fails if either copy drifts. Usage: python3 tests/test_callback.py
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = [
    ROOT / "plugins/clean-contributors/skills/strip-coauthors/SKILL.md",
    ROOT / "README.md",
]

CASES = [
    # (description, input, expected output)
    ("Claude Code trailer",
     b"Fix bug\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n",
     b"Fix bug\n"),
    ("trailer with a model name",
     b"Fix bug\n\nCo-authored-by: Claude Opus 4.6 <noreply@anthropic.com>\n",
     b"Fix bug\n"),
    ("Claude GitHub App",
     b"Fix\n\nCo-authored-by: claude[bot] <209825114+claude[bot]@users.noreply.github.com>\n",
     b"Fix\n"),
    ("keeps other co-authors",
     b"A\n\nCo-authored-by: Bob <bob@example.com>\nCo-authored-by: Claude <noreply@anthropic.com>",
     b"A\n\nCo-authored-by: Bob <bob@example.com>\n"),
    ("keeps a human whose name contains Claude",
     b"Docs\n\nCo-authored-by: Claudette Wu <cw@example.com>\n",
     b"Docs\n\nCo-authored-by: Claudette Wu <cw@example.com>\n"),
    ("leaves unrelated messages byte for byte",
     b"Initial\n\n\n",
     b"Initial\n\n\n"),
    ("leaves a message without trailing newline",
     b"Initial",
     b"Initial"),
]


def load_callback(path):
    text = path.read_text(encoding="utf-8")
    body = text.split("--message-callback '\n", 1)[1].split("\n'\n", 1)[0]
    namespace = {}
    exec("def callback(message):\n" + "\n".join("    " + line for line in body.splitlines()), namespace)
    return namespace["callback"]


def main():
    failed = 0
    for source in SOURCES:
        callback = load_callback(source)
        for description, given, expected in CASES:
            got = callback(given)
            ok = got == expected
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'} {source.name}: {description}")
            if not ok:
                print(f"     expected {expected!r}\n     got      {got!r}")
    print(f"\n{'all passed' if not failed else f'{failed} failed'}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

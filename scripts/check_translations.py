#!/usr/bin/env python3
"""Keeps the .ts files honest against the QML sources.

lupdate is not run locally (the .ts files are hand-edited), so nothing
otherwise notices when the two drift. And the drift is silent: a string with
no entry, or an entry under a context no file uses any more, builds and
ships perfectly and simply comes out in English.

Renaming a page is the sharp edge. Qt keys translations by context, and for
QML the context is the file's base name, so MainPage.qml becoming
PeoplePage.qml orphaned all 31 of its messages in seven locales at once.
"""

import re
import sys
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parent.parent
QML_DIR = ROOT / "qml"
TS_DIR = ROOT / "translations"

TEMPLATE = "harbour-nami.ts"
# English is the source language: it carries only the handful of strings that
# read differently in the UI than in the code, not the whole catalogue
OVERRIDE_ONLY = {"harbour-nami-en.ts"}

QSTR = re.compile(r'qsTr\(\s*"((?:[^"\\]|\\.)*)"')
BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.S)
LINE_COMMENT = re.compile(r"//[^\n]*")


def strip_comments(text):
    """A qsTr() shown in a doc comment is documentation, not a string.

    ActionSheetPage's header comment demonstrates the actions array with a
    qsTr("Rename") in it, and counting that as a real string sends you
    looking for a translation nobody ever needed.
    """
    return LINE_COMMENT.sub("", BLOCK_COMMENT.sub("", text))


def unescape_qml(source):
    """QML escape sequences, the way lupdate would resolve them.

    A "\\n" in a QML literal is a newline in the .ts source, not two
    characters, which is why the .ts files carry literal line breaks inside
    <source>.
    """
    return (source.replace("\\n", "\n").replace("\\t", "\t")
                  .replace("\\r", "\r").replace('\\"', '"')
                  .replace("\\\\", "\\"))


def qml_strings():
    """(context, source) pairs the QML actually asks to translate."""
    found = set()
    for path in sorted(QML_DIR.rglob("*.qml")):
        context = path.stem
        text = strip_comments(path.read_text(encoding="utf-8"))
        for source in QSTR.findall(text):
            found.add((context, unescape_qml(source)))
    return found


def ts_strings(path):
    root = ElementTree.parse(path).getroot()
    found = set()
    for context in root.findall("context"):
        name = context.find("name").text
        for message in context.findall("message"):
            source = message.find("source")
            if source is not None and source.text is not None:
                found.add((name, source.text))
    return found


def report(title, pairs, limit=12):
    print(f"\n{title} ({len(pairs)}):")
    for context, source in sorted(pairs)[:limit]:
        shown = source if len(source) <= 60 else source[:57] + "..."
        print(f"    {context}: {shown}")
    if len(pairs) > limit:
        print(f"    ... and {len(pairs) - limit} more")


def main():
    wanted = qml_strings()
    template = ts_strings(TS_DIR / TEMPLATE)
    problems = 0

    missing = wanted - template
    if missing:
        report(f"{TEMPLATE}: strings the QML uses with no entry", missing)
        problems += len(missing)

    orphaned = template - wanted
    if orphaned:
        report(f"{TEMPLATE}: entries no QML file asks for any more", orphaned)
        problems += len(orphaned)

    for path in sorted(TS_DIR.glob("*.ts")):
        if path.name == TEMPLATE or path.name in OVERRIDE_ONLY:
            continue
        locale = ts_strings(path)

        absent = template - locale
        if absent:
            report(f"{path.name}: missing next to {TEMPLATE}", absent)
            problems += len(absent)

        extra = locale - template
        if extra:
            report(f"{path.name}: not in {TEMPLATE} any more", extra)
            problems += len(extra)

    catalogues = len(list(TS_DIR.glob("*.ts")))
    print(f"\nchecked {len(wanted)} strings across {catalogues} catalogues, "
          f"{problems} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

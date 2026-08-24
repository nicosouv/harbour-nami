#!/usr/bin/env python3
"""Static checks on the QML sources.

Every rule here comes from a bug that actually shipped, so each one carries
the story of what it prevents. Runs anywhere, no Qt needed - qmllint covers
syntax separately, this covers the traps qmllint has nothing to say about.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QML_DIRS = [ROOT / "qml"]

# Start of a property binding: "property int foo: ..." or "readonly property ..."
BINDING_START = re.compile(r"^\s*(readonly\s+)?property\s+\w+(<[^>]+>)?\s+\w+\s*:")
# Start of a function body, where the same call is harmless
FUNCTION_START = re.compile(r"^\s*function\s+\w+\s*\(")


def qml_files():
    for directory in QML_DIRS:
        yield from sorted(directory.rglob("*.qml"))


def strip_comments(line):
    return re.sub(r"//.*$", "", line)


def check_get_in_binding(path, lines):
    """ListModel.get() inside a property binding.

    The wrapper object get() returns is owned by the model, but a binding
    that reads it keeps a dependency guard on it. When the component is
    destroyed the binding's destructor can touch that wrapper after the
    model has released it, which aborts the process with "pure virtual
    method called". Compute it in a function called from a signal handler
    instead. See SelectPersonDialog.updateMatches().
    """
    findings = []
    in_binding = False
    depth = 0
    binding_line = 0

    for number, raw in enumerate(lines, start=1):
        line = strip_comments(raw)

        if not in_binding:
            if BINDING_START.search(line) and not FUNCTION_START.search(line):
                in_binding = True
                binding_line = number
                depth = line.count("{") - line.count("}")
                # A single-line binding ends right here
                if depth <= 0 and ".get(" not in line:
                    in_binding = False
                elif ".get(" in line:
                    findings.append((binding_line, raw.strip()))
                    in_binding = depth > 0
            continue

        if ".get(" in line:
            findings.append((binding_line, line.strip()))
        depth += line.count("{") - line.count("}")
        if depth <= 0:
            in_binding = False

    return findings


def check_unguarded_canvas_api(path, lines):
    """Context2D calls that Qt Quick's Canvas does not implement.

    setLineDash is absent from Qt Quick's context: calling it throws, and the
    exception aborts the whole paint handler, so the canvas renders blank
    rather than merely undashed. TripRouteMap walks its dashes by hand.
    """
    findings = []
    for number, raw in enumerate(lines, start=1):
        line = strip_comments(raw)
        for call in ("setLineDash", "getLineDash", "lineDashOffset"):
            if call in line and "ctx." + call not in line.replace("if (ctx." + call, ""):
                continue
            if call in line and not re.search(r"if\s*\(\s*ctx\." + call, line):
                findings.append((number, line.strip()))
                break
    return findings


def shared_models(lines):
    """Identifiers handed to a pushed component as a property value.

    Those are the models another component binds to while it is alive, and
    the ones clearing is dangerous for.
    """
    text = "\n".join(strip_comments(line) for line in lines)
    names = set()
    for push in re.finditer(r"pageStack\.push\s*\(", text):
        # Crude but sufficient: scan to the matching close paren
        depth = 0
        start = push.end() - 1
        for index in range(start, len(text)):
            if text[index] == "(":
                depth += 1
            elif text[index] == ")":
                depth -= 1
                if depth == 0:
                    args = text[start:index]
                    names.update(re.findall(r"\w+\s*:\s*(\w+)\s*[,}]", args))
                    break
    return names


def check_model_clear(path, lines):
    """clear() on a model handed to another component.

    clear() destroys every delegate at once, including those of a dialog
    still on the page stack and bound to that model - and those handlers
    routinely run while the dialog is being torn down. Update in place with
    set/append/remove, the way PeoplePage and IdentifyFacesPage do.
    """
    shared = shared_models(lines)
    if not shared:
        return []

    findings = []
    for number, raw in enumerate(lines, start=1):
        line = strip_comments(raw)
        match = re.search(r"\b(\w+)\.clear\s*\(", line)
        if match and match.group(1) in shared:
            findings.append((number, line.strip()))
    return findings


# Properties every Item already has. Declaring one of these shadows the
# built-in, and the shadow only reaches the component's own root scope.
ITEM_PROPERTIES = {
    "clip", "state", "states", "opacity", "visible", "enabled", "focus",
    "rotation", "scale", "smooth", "antialiasing", "parent", "children",
    "data", "transform", "x", "y", "z", "width", "height",
    "implicitWidth", "implicitHeight", "baselineOffset", "activeFocus",
}

PROPERTY_DECL = re.compile(
    r"^\s*(?:readonly\s+)?property\s+(?:var|int|real|double|bool|string|url|color|list<[^>]+>|[A-Z]\w*)\s+(\w+)\s*[:;]?")


def check_shadowed_item_property(path, lines):
    """A property named like one Item already has.

    The declaration shadows the built-in, but only in the component's own
    root scope. Inside any nested Item, a bare name resolves to that Item's
    inherited property instead, silently and with a plausible type.

    MemoryPlayer declared `property var edit` as `clip`. At the root it read
    back as the edit; inside its Loader it read back as the Loader's own
    boolean, which is false, so the Loader's `active` condition was never
    true and every clip played silently. Nothing failed, nothing logged.
    """
    findings = []
    for number, raw in enumerate(lines, start=1):
        line = strip_comments(raw)
        match = PROPERTY_DECL.search(line)
        if match and match.group(1) in ITEM_PROPERTIES:
            findings.append((number, line.strip()))
    return findings


# Types Silica and QtQuick already define. A file in qml/components/ named
# after one of these shadows it in every file that imports that directory.
PLATFORM_TYPES = {
    # Silica
    "SectionHeader", "PageHeader", "Page", "Button", "Label", "TextField",
    "TextArea", "Slider", "Switch", "TextSwitch", "ComboBox", "ContextMenu",
    "MenuItem", "Dialog", "DialogHeader", "ViewPlaceholder", "SearchField",
    "IconButton", "BackgroundItem", "ListItem", "RemorseItem", "Separator",
    "SilicaListView", "SilicaGridView", "SilicaFlickable", "PullDownMenu",
    "PushUpMenu", "BusyIndicator", "GlassItem", "DockedPanel", "ProgressBar",
    "ValueButton", "Icon", "Theme", "Formatter",
    # QtQuick
    "Item", "Rectangle", "Image", "Text", "Row", "Column", "Grid", "Flow",
    "Repeater", "Loader", "Timer", "Connections", "Component", "MouseArea",
    "Flickable", "ListView", "GridView", "ListModel", "Animation", "Gradient",
}


def check_shadowed_platform_type(path, lines):
    """A component named after a type Silica or QtQuick already defines.

    The local one wins in every file that imports its directory, silently and
    at load time. SectionPageHeader started life as SectionHeader and took
    YearDetailPage down with it: that page uses Silica's, which has a text
    property the local one did not, so the whole page failed to load.
    """
    if path.parent.name != "components" or path.stem not in PLATFORM_TYPES:
        return []
    return [(1, f"{path.stem} is already a Silica or QtQuick type")]


CHECKS = [
    ("ListModel.get() inside a property binding", check_get_in_binding),
    ("unguarded Canvas dash API", check_unguarded_canvas_api),
    ("clear() on a shared people model", check_model_clear),
    ("property shadows one Item already has", check_shadowed_item_property),
    ("component name shadows a platform type", check_shadowed_platform_type),
]


def main():
    failures = 0
    checked = 0

    for path in qml_files():
        checked += 1
        lines = path.read_text(encoding="utf-8").splitlines()
        for title, check in CHECKS:
            for number, snippet in check(path, lines):
                rel = path.relative_to(ROOT)
                print(f"{rel}:{number}: {title}")
                print(f"    {snippet}")
                print(f"    {check.__doc__.strip().splitlines()[0]}")
                failures += 1

    print(f"\nchecked {checked} QML files, {failures} problem(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

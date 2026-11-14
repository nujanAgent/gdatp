"""Holds GDatp's tools.json to the schema form every model provider receives.

A host passes each tool's inputSchema to a model provider, and providers take an object at the root, a type on every
property and items on every array. A property without a type is sent as a string by some hosts and dropped by some
providers, so a tool's own description of it is the only thing a model has to go on.

Every request carries every tool's definition, so a tool's own description is at most DESCRIPTION_MAX characters: what
a model needs to choose the tool. The detail goes in its parameters' descriptions.

Run from the repository root: python gdatp/checks/tools_schema_check.py [another tools.json]
"""

import json
import re
import sys
from pathlib import Path

TOOLS = Path("platform/android/java/editor/src/main/assets/gdatp/tools.json")
MANIFEST = Path("platform/android/java/editor/src/main/res/xml/atp_provider.xml")
DESCRIPTION_MAX = 120


def check(path: str, schema, problems: list) -> None:
    if not isinstance(schema, dict):
        problems.append(f"{path}: not a schema object")
        return
    kind = schema.get("type")
    if not isinstance(kind, str) and "enum" not in schema and "const" not in schema:
        problems.append(f"{path}: no single type")
    if kind == "array":
        if "items" not in schema:
            problems.append(f"{path}: an array without items")
        else:
            check(f"{path}[]", schema["items"], problems)
    for name, sub in (schema.get("properties") or {}).items():
        check(f"{path}.{name}", sub, problems)


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else TOOLS
    tools = json.loads(path.read_text(encoding="utf-8"))["tools"]
    problems: list = []
    groups = set(re.findall(r'<group\s+id="(\w+)"', MANIFEST.read_text(encoding="utf-8")))
    for tool in tools:
        root = tool.get("inputSchema")
        name = tool.get("name", "?")
        description = tool.get("description")
        if not isinstance(description, str) or not description.strip():
            problems.append(f"{name}: no description")
        elif len(description) > DESCRIPTION_MAX:
            problems.append(f"{name}: a description of {len(description)} characters, over {DESCRIPTION_MAX}")
        group = (tool.get("_meta") or {}).get("com.nujan-agent.atp/group")
        if group is not None and group not in groups:
            problems.append(f"{name}: group {group} is not one the manifest declares, so no host is ever granted this tool")
        if not isinstance(root, dict) or root.get("type") != "object" or not isinstance(root.get("properties"), dict):
            problems.append(f"{name}: the root is not an object with properties")
            continue
        for key in ("oneOf", "anyOf", "allOf"):
            if key in root:
                problems.append(f"{name}: a root {key}")
        for prop, sub in root["properties"].items():
            check(f"{name}.{prop}", sub, problems)
    if problems:
        print("tools.json definitions a provider would drop or retype, or that are too long:")
        print("\n".join(problems))
        return 1
    print(f"{len(tools)} tools, every parameter typed, every description at most {DESCRIPTION_MAX} characters")
    return 0


if __name__ == "__main__":
    sys.exit(main())

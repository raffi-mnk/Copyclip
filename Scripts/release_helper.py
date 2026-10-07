#!/usr/bin/env python3
"""Release helpers used by release.sh.

notes <version> <markdown|html>
    Prints that version's section of CHANGELOG.md.
add-item <version> <build> <url> <signature> <length> [appcast]
    Adds the version to the top of the appcast, with its CHANGELOG notes.
"""
import html
import re
import sys
from email.utils import formatdate
from pathlib import Path

root = Path(__file__).resolve().parent.parent


def changelog_section(version):
    text = (root / "CHANGELOG.md").read_text()
    match = re.search(rf"^## {re.escape(version)}\b.*?$\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not match or not match.group(1).strip():
        sys.exit(f"CHANGELOG.md has no notes under '## {version}'.")
    return match.group(1).strip()


def to_html(markdown):
    def inline(text):
        text = html.escape(text)
        text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
        return re.sub(r"`(.+?)`", r"<code>\1</code>", text)

    parts, items = [], []
    for line in markdown.splitlines() + [""]:
        if line.startswith("- "):
            items.append(f"<li>{inline(line[2:].strip())}</li>")
            continue
        if items:
            parts.append("<ul>" + "".join(items) + "</ul>")
            items = []
        if line.strip():
            parts.append(f"<p>{inline(line.strip())}</p>")
    return "\n".join(parts)


def add_item(version, build, url, signature, length, appcast_path=None):
    appcast = Path(appcast_path) if appcast_path else root / "appcast.xml"
    text = appcast.read_text()
    if f"<sparkle:shortVersionString>{version}</sparkle:shortVersionString>" in text:
        sys.exit(f"The appcast already lists {version}.")
    item = f"""    <item>
      <title>Version {version}</title>
      <pubDate>{formatdate(localtime=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
{to_html(changelog_section(version))}
      ]]></description>
      <enclosure url="{html.escape(url)}" type="application/octet-stream"
                 sparkle:edSignature="{signature}" length="{length}"/>
    </item>
"""
    marker = "    <language>en</language>\n"
    if marker not in text:
        sys.exit("The appcast is missing its <language> line.")
    appcast.write_text(text.replace(marker, marker + item, 1))


if __name__ == "__main__":
    command, *args = sys.argv[1:] or [""]
    if command == "notes" and len(args) == 2:
        section = changelog_section(args[0])
        print(to_html(section) if args[1] == "html" else section)
    elif command == "add-item" and len(args) in (5, 6):
        add_item(*args)
    else:
        sys.exit(__doc__)

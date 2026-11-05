#!/usr/bin/env python3
"""Writes dist/appcast.xml, the Sparkle feed, for the signed and zipped build/Kex.app."""
import datetime
import email.utils
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

version = sys.argv[1]
archive = Path("dist/Kex.app.zip")
info = plistlib.loads(Path("build/Kex.app/Contents/Info.plist").read_bytes())
assert info["CFBundleShortVersionString"] == version
signature = Path("dist/signature.txt").read_text().strip()
assert re.fullmatch(r"[A-Za-z0-9+/]{86}==", signature), "Invalid Ed25519 signature"

# Sparkle shows this in its update window: the system font, the system's light or dark look, and a way to the rest.
NOTES_PAGE = """<!doctype html>
<meta charset="utf-8">
<style>
  :root { color-scheme: light dark; }
  body { font: 13px/1.45 -apple-system, sans-serif; margin: 10px 14px; }
  h3 { font-size: 13px; margin: 14px 0 4px; }
  h3:first-child, p:first-child { margin-top: 0; }
  ul { margin: 4px 0; padding-left: 18px; }
  li { margin: 3px 0; }
  code { font: 12px ui-monospace, monospace; }
  footer { margin-top: 14px; opacity: 0.6; }
</style>
{notes}
<footer>Every release: <a href="https://dinky.rodeo/changelog/">dinky.rodeo/changelog</a></footer>
"""


def release_notes(version):
    """The version's section of CHANGELOG.md as a page for Sparkle, rendered by GitHub. None without one."""
    lines = Path("CHANGELOG.md").read_text().splitlines()
    heading = f"## {version}"
    if heading not in lines:
        return None
    body = []
    for line in lines[lines.index(heading) + 1:]:
        if line.startswith("## "):
            break
        body.append(line)
    text = "\n".join(body).strip()
    if not text:
        return None
    html = subprocess.run(["gh", "api", "markdown", "-f", "mode=gfm", "-f", "context=mikker/Dinky", "-f", f"text={text}"],
                          check=True, capture_output=True, text=True).stdout
    return NOTES_PAGE.replace("{notes}", html.strip())


ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", ns)
rss = ET.Element("rss", version="2.0")
channel = ET.SubElement(rss, "channel")
ET.SubElement(channel, "title").text = "Kex"
item = ET.SubElement(channel, "item")
ET.SubElement(item, "title").text = version
ET.SubElement(item, "pubDate").text = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
ET.SubElement(item, f"{{{ns}}}minimumSystemVersion").text = info["LSMinimumSystemVersion"]
notes = release_notes(version)
if notes:
    ET.SubElement(item, "description").text = notes
else:
    ET.SubElement(item, f"{{{ns}}}releaseNotesLink").text = f"https://github.com/mikker/Dinky/releases/tag/v{version}"
ET.SubElement(item, "enclosure", {
    "url": f"https://github.com/mikker/Dinky/releases/download/v{version}/Kex.app.zip",
    "length": str(archive.stat().st_size),
    "type": "application/octet-stream",
    f"{{{ns}}}version": info["CFBundleVersion"],
    f"{{{ns}}}shortVersionString": version,
    f"{{{ns}}}edSignature": signature,
})
ET.indent(rss)
ET.ElementTree(rss).write("dist/appcast.xml", encoding="utf-8", xml_declaration=True)

"""Check the links between the Markdown files of a repository.

check-links [owner/repo]

Relative links have to reach a file, and a #fragment a heading in it. With owner/repo, links to
https://github.com/<owner/repo>/blob/main/... are checked the same way, against the files here.
Other web links aren't followed.
"""

import os
import re
import sys

repo = sys.argv[1] if len(sys.argv) > 1 else None
blob = re.compile(rf"https://github\.com/{re.escape(repo)}/blob/main/([^#]+)(?:#(.*))?$") if repo else None


def slug(heading):
    # GitHub's: lower case, punctuation dropped except - and _, spaces to hyphens
    heading = re.sub(r"[`*\[\]()]", "", heading.strip().lower())
    return re.sub(r"[^\w\- ]", "", heading).replace(" ", "-")


def anchors(path):
    with open(path, encoding="utf-8") as f:
        text = re.sub(r"^```.*?^```", "", f.read(), flags=re.S | re.M)
    return {slug(m) for m in re.findall(r"^#+\s+(.*)", text, flags=re.M)}


def markdown_files():
    for root, dirs, files in os.walk("."):
        # hidden folders hold no docs, apart from .github's templates
        dirs[:] = [d for d in dirs if not d.startswith(".") or d == ".github"]
        for name in files:
            if name.endswith(".md"):
                yield os.path.normpath(os.path.join(root, name))


bad = 0
for md in sorted(markdown_files()):
    with open(md, encoding="utf-8") as f:
        text = re.sub(r"^```.*?^```", "", f.read(), flags=re.S | re.M)
    for target in re.findall(r"\]\(([^)\s]+)\)", text) + re.findall(r'src="([^"]+)"', text):
        if re.match(r"^[a-z]+:", target):
            match = blob.match(target) if blob else None
            if not match:
                continue
            path, fragment = os.path.normpath(match.group(1)), match.group(2)
        else:
            rel, _, fragment = target.partition("#")
            path = os.path.normpath(os.path.join(os.path.dirname(md), rel)) if rel else md
        if not os.path.exists(path):
            print(f"{md}: {target}: no such file")
            bad += 1
        elif fragment and path.endswith(".md") and fragment not in anchors(path):
            print(f"{md}: {target}: no such heading")
            bad += 1

sys.exit(1 if bad else 0)

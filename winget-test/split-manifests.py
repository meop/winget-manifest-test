# Splits `komac update --dry-run` output into manifest files, named as in
# winget-pkgs: <id>.yaml, <id>.installer.yaml, <id>.locale.<locale>.yaml.
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text().replace("\r\n", "\n")
out = Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)

docs = re.split(r"(?m)^(?=# Created with komac)", text)[1:]
if not docs:
    sys.exit("no manifests in komac output")
for doc in docs:
    doc = doc.strip() + "\n"
    ident = re.search(r"(?m)^PackageIdentifier: (\S+)", doc).group(1)
    kind = re.search(r"(?m)^ManifestType: (\S+)", doc).group(1)
    if kind == "version":
        name = f"{ident}.yaml"
    elif kind == "installer":
        name = f"{ident}.installer.yaml"
    else:
        locale = re.search(r"(?m)^PackageLocale: (\S+)", doc).group(1)
        name = f"{ident}.locale.{locale}.yaml"
    (out / name).write_text(doc)
    print(out / name)

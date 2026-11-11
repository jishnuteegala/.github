"""Write or compare a sorted SHA-256 manifest of a built dist/ directory.

write <dist> <out>         write the manifest of <dist> to <out>
compare <dist> <manifest>  compare <dist> with a manifest written by CI; a
                           missing <manifest> warns and passes
select <listing>           print the id of the newest unexpired artifact in an
                           artifacts API listing that a run of the repository
                           itself uploaded, not a fork pull request run
"""

import hashlib
import json
import os
import sys
from pathlib import Path


def entries(dist: Path) -> dict[str, str]:
    return {
        path.relative_to(dist).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in dist.rglob("*")
        if path.is_file()
    }


def render(manifest: dict[str, str]) -> str:
    return "".join(f"{digest}  {name}\n" for name, digest in sorted(manifest.items()))


def parse(text: str) -> dict[str, str]:
    return {name: digest for digest, name in (line.split("  ", 1) for line in text.splitlines())}


def summary(text: str) -> None:
    if path := os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(path, "a", encoding="utf-8") as file:
            file.write(text + "\n")


def write(dist: Path, out: Path) -> int:
    manifest = entries(dist) if dist.is_dir() else {}
    if not manifest:
        print(f"::error::No files under {dist}; build the app before writing its manifest.")
        return 1
    out.write_text(render(manifest), encoding="utf-8", newline="\n")
    print(f"Wrote the SHA-256 manifest of {len(manifest)} files under {dist} to {out}.")
    return 0


def compare(dist: Path, ci_manifest: Path) -> int:
    if not ci_manifest.is_file():
        message = (
            "No CI dist manifest exists for this source tree (no CI run uploaded one, it expired,"
            " or CI had not finished), so this build was not compared with CI."
        )
        print(f"::warning::{message}")
        summary(f"> [!WARNING]\n> {message}")
        return 0
    expected = parse(ci_manifest.read_text(encoding="utf-8"))
    actual = entries(dist) if dist.is_dir() else {}
    problems = [
        *(f"only in CI: {name}" for name in sorted(expected.keys() - actual.keys())),
        *(f"only in this build: {name}" for name in sorted(actual.keys() - expected.keys())),
        *(f"changed: {name}" for name in sorted(expected.keys() & actual.keys()) if expected[name] != actual[name]),
    ]
    if problems:
        print(f"::error::{dist} differs from the CI build of the same source tree.")
        print("\n".join(problems))
        summary("Dist manifest mismatch with the CI build:\n\n" + "\n".join(f"- `{p}`" for p in problems))
        return 1
    print(f"{dist} matches the CI build: {len(actual)} files.")
    summary(f"Dist manifest matches the CI build of the same source tree ({len(actual)} files).")
    return 0


def trusted(artifact: dict) -> bool:
    run = artifact.get("workflow_run") or {}
    return not artifact["expired"] and run.get("repository_id") is not None and run.get("head_repository_id") == run["repository_id"]


def select(listing: Path) -> int:
    artifacts = [a for a in json.loads(listing.read_text(encoding="utf-8"))["artifacts"] if trusted(a)]
    if artifacts:
        print(max(artifacts, key=lambda a: a["created_at"])["id"])
    return 0


def main(argv: list[str]) -> int:
    commands = {"write": (write, 2), "compare": (compare, 2), "select": (select, 1)}
    command, arity = commands.get(argv[0] if argv else "", (None, -1))
    if len(argv) - 1 != arity:
        print(__doc__, file=sys.stderr)
        return 2
    return command(*map(Path, argv[1:]))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

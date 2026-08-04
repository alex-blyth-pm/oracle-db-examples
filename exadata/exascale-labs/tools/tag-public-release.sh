#!/usr/bin/env bash

# Create and optionally push the public release tag after the candidate PR merges.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  tools/tag-public-release.sh --version VERSION --public-repo <path> [options]

Required arguments:
  --version VERSION      Candidate version, for example 0.3.1.
  --public-repo <path>   Local clone of alex-blyth-pm/oracle-db-examples.

Options:
  --push                 Push the annotated public tag to origin.
  --dry-run              Validate without creating or pushing the tag.
  --help                 Show this help.

The script requires a clean public checkout on main that matches origin/main.
It verifies PUBLICATION.md identifies the requested candidate version, then
creates exadata-exascale-labs-v<VERSION> on the public merge commit.
EOF
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

version=''
public_repo=''
push_tag=false
dry_run=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            version=${2:-}
            shift 2
            ;;
        --public-repo)
            public_repo=${2:-}
            shift 2
            ;;
        --push)
            push_tag=true
            shift
            ;;
        --dry-run)
            dry_run=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            fail "Unknown argument: $1"
            ;;
    esac
done

[[ -n "$version" ]] || fail '--version is required.'
[[ -n "$public_repo" ]] || fail '--public-repo is required.'
[[ -d "$public_repo/.git" ]] || fail '--public-repo must be a local Git clone.'

public_repo=$(cd "$public_repo" && pwd)
[[ -z $(git -C "$public_repo" status --porcelain) ]] \
    || fail 'The public repository has uncommitted or untracked files.'
[[ $(git -C "$public_repo" branch --show-current) == main ]] \
    || fail 'Run this script from the public main branch.'

git -C "$public_repo" fetch origin main
head_commit=$(git -C "$public_repo" rev-parse HEAD)
origin_main_commit=$(git -C "$public_repo" rev-parse origin/main)
[[ "$head_commit" == "$origin_main_commit" ]] \
    || fail 'Local public main does not match origin/main. Merge and pull the candidate first.'

publication_file="$public_repo/exadata/exascale-labs/PUBLICATION.md"
[[ -f "$publication_file" ]] \
    || fail 'PUBLICATION.md was not found in exadata/exascale-labs.'
grep -Fqx -- "- Candidate version: \`${version}\`" "$publication_file" \
    || fail "PUBLICATION.md does not identify candidate version ${version}."

release_tag="exadata-exascale-labs-v${version}"

if git -C "$public_repo" rev-parse -q --verify "refs/tags/${release_tag}" >/dev/null; then
    [[ $(git -C "$public_repo" cat-file -t "$release_tag") == tag ]] \
        || fail "${release_tag} exists but is not annotated."
    tag_commit=$(git -C "$public_repo" rev-parse "${release_tag}^{commit}")
    [[ "$tag_commit" == "$head_commit" ]] \
        || fail "${release_tag} points to ${tag_commit}, not public main ${head_commit}."
    printf 'Annotated public tag already exists locally: %s\n' "$release_tag"
elif [[ "$dry_run" == true ]]; then
    printf 'Would create annotated public tag: %s on %s\n' "$release_tag" "$head_commit"
else
    git -C "$public_repo" tag -a "$release_tag" -m "Exadata Exascale Labs ${release_tag}"
    printf 'Created annotated public tag: %s\n' "$release_tag"
fi

if [[ "$push_tag" == true ]]; then
    if [[ "$dry_run" == true ]]; then
        printf 'Would push public tag: %s\n' "$release_tag"
    else
        git -C "$public_repo" push origin "$release_tag"
        printf 'Pushed public tag: %s\n' "$release_tag"
    fi
fi

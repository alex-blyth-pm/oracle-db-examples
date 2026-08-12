#!/usr/bin/env bash

# Create and optionally push the annotated internal release tag for VERSION.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  tools/create-release-tag.sh [options]

Options:
  --version VERSION  Release version. Defaults to the value in VERSION.
  --push             Push the annotated tag to origin after validation.
  --dry-run          Validate without creating or pushing the tag.
  --help             Show this help.

The script requires a clean internal checkout on main that matches origin/main.
It creates an annotated v<VERSION> tag on HEAD. Pushing this tag does not require
a merge request because it references an already merged main commit.
EOF
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

requested_version=''
push_tag=false
dry_run=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            requested_version=${2:-}
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

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) \
    || fail 'Run this script from within the internal labs repository.'

[[ -z $(git -C "$repo_root" status --porcelain) ]] \
    || fail 'The internal repository has uncommitted or untracked files.'
[[ $(git -C "$repo_root" branch --show-current) == main ]] \
    || fail 'Run this script from the internal main branch.'

version=$(tr -d '[:space:]' < "$repo_root/VERSION")
[[ -n "$version" ]] || fail 'VERSION is empty.'

if [[ -n "$requested_version" && "$requested_version" != "$version" ]]; then
    fail "--version ${requested_version} does not match VERSION ${version}."
fi

release_tag="v${version}"

git -C "$repo_root" fetch origin main
head_commit=$(git -C "$repo_root" rev-parse HEAD)
origin_main_commit=$(git -C "$repo_root" rev-parse origin/main)
[[ "$head_commit" == "$origin_main_commit" ]] \
    || fail 'Local main does not match origin/main. Merge and push the release first.'

if git -C "$repo_root" rev-parse -q --verify "refs/tags/${release_tag}" >/dev/null; then
    [[ $(git -C "$repo_root" cat-file -t "$release_tag") == tag ]] \
        || fail "${release_tag} exists but is not annotated."
    tag_commit=$(git -C "$repo_root" rev-parse "${release_tag}^{commit}")
    [[ "$tag_commit" == "$head_commit" ]] \
        || fail "${release_tag} points to ${tag_commit}, not current main ${head_commit}."
    printf 'Annotated tag already exists locally: %s\n' "$release_tag"
elif [[ "$dry_run" == true ]]; then
    printf 'Would create annotated tag: %s on %s\n' "$release_tag" "$head_commit"
else
    git -C "$repo_root" tag -a "$release_tag" -m "Exadata Exascale Labs ${release_tag}"
    printf 'Created annotated tag: %s\n' "$release_tag"
fi

if [[ "$push_tag" == true ]]; then
    if [[ "$dry_run" == true ]]; then
        printf 'Would push tag: %s\n' "$release_tag"
    else
        git -C "$repo_root" push origin "$release_tag"
        printf 'Pushed tag: %s\n' "$release_tag"
    fi
fi

printf 'Next: stage a public candidate with tools/publish-public-snapshot.sh --tag %s.\n' "$release_tag"

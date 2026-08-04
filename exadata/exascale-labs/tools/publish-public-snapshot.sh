#!/usr/bin/env bash

# Prepare a reviewable public staging candidate from an annotated internal tag.
# The script never creates a pull request.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  tools/publish-public-snapshot.sh --tag <release-tag> --public-repo <path> [options]

Required arguments:
  --tag <release-tag>       Annotated tag in this repository, for example v0.3.1.
  --public-repo <path>      Clean local clone of alex-blyth-pm/oracle-db-examples.

Options:
  --branch <branch>         Public candidate branch. Defaults to
                            exadata-exascale-labs-<release-tag>.
  --destination <path>      Destination within the public repository. Defaults to
                            exadata/exascale-labs.
  --commit                  Commit the prepared candidate in the public repository.
  --push                    Push the committed candidate branch to origin.
  --dry-run                 Validate the source export without changing the public clone.
  --help                    Show this help text.

Each candidate is a complete, cumulative snapshot of the tagged internal source.
The script creates its branch from origin/main in the public repository, exports
the tagged source with docs/blogs excluded, updates publication metadata, and
adds the landing-page link when it is missing. Use --commit to create the local
candidate commit and --push to publish it. Review and open the public pull request
after the script completes.
EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

release_tag=''
public_repo=''
public_branch=''
destination='exadata/exascale-labs'
commit_candidate=false
push_candidate=false
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      release_tag=${2:-}
      shift 2
      ;;
    --public-repo)
      public_repo=${2:-}
      shift 2
      ;;
    --branch)
      public_branch=${2:-}
      shift 2
      ;;
    --destination)
      destination=${2:-}
      shift 2
      ;;
    --commit)
      commit_candidate=true
      shift
      ;;
    --push)
      push_candidate=true
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

[[ -n "$release_tag" ]] || fail '--tag is required.'
[[ -n "$public_repo" ]] || fail '--public-repo is required.'
if [[ "$push_candidate" == true && "$commit_candidate" == false ]]; then
  fail '--push requires --commit.'
fi
[[ "$destination" == exadata/* && "$destination" != */../* && "$destination" != *'/..' ]] \
  || fail '--destination must be a relative path below exadata/.'

source_repo=$(git rev-parse --show-toplevel 2>/dev/null) \
  || fail 'Run this script from within the internal labs repository.'

[[ $(git -C "$source_repo" cat-file -t "$release_tag" 2>/dev/null || true) == tag ]] \
  || fail "${release_tag} must be an annotated tag."

source_commit=$(git -C "$source_repo" rev-parse "${release_tag}^{commit}")
release_version=$(git -C "$source_repo" show "${release_tag}:VERSION" 2>/dev/null | tr -d '[:space:]') \
  || fail "${release_tag} does not contain VERSION."

[[ -n "$release_version" ]] || fail "${release_tag} contains an empty VERSION."
[[ "$release_tag" == "v${release_version}" ]] \
  || fail "${release_tag} does not match VERSION ${release_version}."
[[ -d "$public_repo/.git" ]] || fail '--public-repo must be a local Git clone.'

public_repo=$(cd "$public_repo" && pwd)
[[ -n "$public_branch" ]] || public_branch="exadata-exascale-labs-${release_tag}"

if [[ "$dry_run" == false ]]; then
  if [[ -n $(git -C "$public_repo" status --porcelain) ]]; then
    fail 'The public repository has uncommitted or untracked files.'
  fi

fi

staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/exadata-exascale-export.XXXXXX")
cleanup() {
  rm -rf "$staging_dir"
}
trap cleanup EXIT

git -C "$source_repo" archive --format=tar "$release_tag" -- . ':(exclude)docs/blogs' \
  | tar -xf - -C "$staging_dir"

[[ ! -e "$staging_dir/docs/blogs" ]] \
  || fail 'The public export unexpectedly contains docs/blogs.'
[[ -f "$staging_dir/README.md" ]] || fail 'The source export does not contain README.md.'

# The public repository ignores dotfiles globally, but the tagged source
# intentionally includes tracked dotfiles. Permit only ignored destination
# files that the source export will replace; preserve the guard for local files
# that are outside the export.
if [[ "$dry_run" == false ]]; then
  while IFS= read -r ignored_file; do
    export_path=${ignored_file#"$destination"/}
    [[ -e "$staging_dir/$export_path" ]] \
      || fail "The public destination contains an ignored file outside the source export: ${ignored_file}. Remove or relocate it first."
  done < <(git -C "$public_repo" ls-files --others --ignored --exclude-standard -- "$destination")
fi

if [[ "$dry_run" == true ]]; then
  printf 'Validated public export for %s (%s).\n' "$release_tag" "$source_commit"
  printf 'No changes were made to %s.\n' "$public_repo"
  exit 0
fi

git -C "$public_repo" fetch origin main

if git -C "$public_repo" show-ref --verify --quiet "refs/heads/${public_branch}"; then
  fail "Public branch already exists locally: ${public_branch}"
fi

if git -C "$public_repo" ls-remote --exit-code --heads origin "${public_branch}" >/dev/null 2>&1; then
  fail "Public branch already exists on origin: ${public_branch}"
fi

git -C "$public_repo" switch -c "$public_branch" origin/main
public_base_commit=$(git -C "$public_repo" rev-parse HEAD)
git -C "$public_repo" rm -r --ignore-unmatch -- "$destination"
mkdir -p "$public_repo/$destination"

tar -C "$staging_dir" -cf - . | tar -C "$public_repo/$destination" -xf -
diff -qr "$staging_dir" "$public_repo/$destination"

publication_file="$public_repo/$destination/PUBLICATION.md"
printf '%s\n' \
  '# Publication Metadata' \
  '' \
  'This directory is a generated public staging candidate from the Exadata Exascale Labs repository.' \
  'It is not an official public release until its pull request merges.' \
  '' \
  "- Internal release tag: \`${release_tag}\`" \
  "- Internal source commit: \`${source_commit}\`" \
  "- Candidate version: \`${release_version}\`" \
  "- Public base commit: \`${public_base_commit}\`" \
  "- Public destination: \`${destination}\`" \
  > "$publication_file"

landing_readme="$public_repo/exadata/README.md"
landing_link='- [Exadata Exascale Labs](./exascale-labs/) - Hands-on Oracle AI Database 26ai labs for Exadata Exascale snapshot and cloning workflows.'

[[ -f "$landing_readme" ]] || fail 'The public repository does not contain exadata/README.md.'

if ! grep -Fqx -- "$landing_link" "$landing_readme"; then
  landing_tmp=$(mktemp "${TMPDIR:-/tmp}/exadata-landing-readme.XXXXXX")
  awk -v link="$landing_link" '
    { print }
    !inserted && $0 == "## Examples" {
      getline
      print
      print link
      inserted = 1
    }
    END {
      if (!inserted) {
        exit 1
      }
    }
  ' "$landing_readme" > "$landing_tmp" \
    || fail 'Could not locate the Examples section in exadata/README.md.'
  mv "$landing_tmp" "$landing_readme"
fi

git -C "$public_repo" diff --check
[[ ! -e "$public_repo/$destination/docs/blogs" ]] \
  || fail 'The public destination contains docs/blogs after staging.'

if [[ "$commit_candidate" == true ]]; then
  # The public repository's global ignore rules also apply within the staged
  # destination, so force-add the validated source snapshot.
  git -C "$public_repo" add -f -- "$destination"
  git -C "$public_repo" add -- exadata/README.md
  git -C "$public_repo" commit -m "Stage Exadata Exascale Labs ${release_version}"
fi

if [[ "$push_candidate" == true ]]; then
  git -C "$public_repo" push -u origin "$public_branch"
fi

printf 'Public staging candidate prepared: %s\n' "$public_branch"
printf 'Internal source: %s (%s)\n' "$release_tag" "$source_commit"
printf 'Public base: origin/main (%s)\n' "$public_base_commit"
printf 'Review with: git -C %s status --short\n' "$public_repo"

if [[ "$commit_candidate" == true ]]; then
  if [[ "$push_candidate" == true ]]; then
    printf 'Candidate branch pushed to origin.\n'
  else
    printf 'Push with: git -C %s push -u origin %s\n' "$public_repo" "$public_branch"
  fi
else
  printf 'Commit with: git -C %s add %s exadata/README.md && git -C %s commit -m "Stage Exadata Exascale Labs %s"\n' \
    "$public_repo" "$destination" "$public_repo" "$release_version"
fi

printf 'Then open a pull request from %s to main when this candidate is ready.\n' "$public_branch"

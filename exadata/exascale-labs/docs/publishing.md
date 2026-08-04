# Staging and Publishing Public Snapshots

The internal repository is the source of truth. The public repository receives
cumulative staging candidates under `exadata/exascale-labs/`. A staging
candidate is not an official public release until its pull request merges.

## Candidate Model

Each candidate contains the complete labs repository at one internal annotated
tag. Candidates are not incremental patches to earlier public candidates.

This lets internal development move ahead of external review. For example, if
public candidate branches exist for `v0.2.1` and `v0.2.3`, and `v0.2.3`
contains all required changes, submit only the `v0.2.3` candidate. Do not merge
the two candidate branches together.

Create every candidate branch from the official public `main` branch. That
keeps each candidate independently reviewable and lets a newer candidate
supersede an older unsubmitted one.

## Create a Staging Candidate

1. Merge the internal candidate changes to internal `main` and set `VERSION`.
2. Create and push the matching annotated internal tag:

   ```bash
   tools/create-release-tag.sh --push
   ```

   The helper requires a clean local `main` that matches `origin/main`. It
   creates `v<VERSION>` on that merged commit and pushes only the tag. No merge
   request is required for this tag push.
3. Start from a clean local clone of `alex-blyth-pm/oracle-db-examples`.
4. Run the publication script from the internal repository:

   ```bash
   tools/publish-public-snapshot.sh \
     --tag v0.3.1 \
     --public-repo /path/to/oracle-db-examples \
     --commit \
     --push
   ```

The script creates `exadata-exascale-labs-v0.3.1` from public `origin/main`,
exports the complete tagged internal snapshot, and records the source tag,
source commit, and public base commit in `PUBLICATION.md`.

`--commit` creates the local public candidate commit. `--push` pushes that
candidate branch. Omit either option when you want to complete that step
manually. The script never opens a pull request.

## Promote a Candidate

1. Review the staged candidate and open a pull request from its branch to public
   `main` when ready
   for Oracle review.
2. After the public pull request merges, pull public `main` and create the
   annotated public tag:

   ```bash
   tools/tag-public-release.sh \
     --version 0.3.1 \
     --public-repo /path/to/oracle-db-examples \
     --push
   ```

   The helper verifies the merged public snapshot records the requested
   candidate version before creating `exadata-exascale-labs-v0.3.1`.

Older candidate branches may be retained for traceability or deleted after a
newer candidate supersedes them. Do not call a candidate branch or its commit a
public release before it merges.

## Safeguards

The script requires an annotated source tag whose name matches `VERSION`, and a
clean public clone. It refuses to reuse an existing local or remote candidate
branch. It exports the tagged source with `docs/blogs/` excluded, replaces only
the public labs directory, records traceability metadata in `PUBLICATION.md`,
and runs Git whitespace validation. It can commit and push only when explicitly
requested, and it never opens pull requests.

Use `--dry-run` to validate the export without changing the public clone.

#!/usr/bin/env bash
# Assemble the firmware source for the edge switches, fresh on every run:
#
#   1. upstream main ($UPSTREAM)
#   2. + the patch branches of $PATCH_FORK (the list it applies itself when
#        $PATCH_FORK_BRANCHES is "auto"), latest version, skipping what upstream
#        already contains and skipping (with a note) anything that conflicts
#   3. + the upstream pull requests in $UPSTREAM_PRS, the same way
#   4. + the overlay files from this branch ($OVERLAY): switch configs and
#        board profiles; a board file upstream now ships itself wins
#
# Writes $WORK/src (the tree to build), $WORK/manifest.txt (what went in, used
# as the change fingerprint) and $WORK/notes.md (release notes fragment).
# Needs git; uses gh only when available (to compare with the last release).
set -euo pipefail

WORK=${WORK:-$PWD/work}
LOCAL=${LOCAL:-$PWD}            # checkout of this branch
GH=$(command -v gh || true)
mkdir -p "$WORK"; rm -rf "$WORK/src"
MAN="$WORK/manifest.txt"; NOTES="$WORK/notes.md"; : > "$MAN"; : > "$NOTES"
note() { echo "$*" >> "$NOTES"; }
gh_url() { echo "https://github.com/$1.git"; }

git clone --quiet "$(gh_url "$UPSTREAM")" "$WORK/src"
cd "$WORK/src"
git config user.name "edge-firmware"; git config user.email "edge-firmware@localhost"
UP=$(git rev-parse HEAD)
echo "upstream $UPSTREAM $UP" >> "$MAN"

# Cherry-pick the commits of FETCH_HEAD that the tree does not have yet.
# $1: label for notes/manifest. Returns 0 always; reports what happened.
apply_fetched() {
	local label=$1 tip picks c ok=1
	tip=$(git rev-parse FETCH_HEAD)
	picks=""
	for c in $(git cherry HEAD FETCH_HEAD | sed -n 's/^+ //p'); do
		# merge commits (e.g. "Merge branch 'main'" inside a PR) are skipped
		[ "$(git rev-list --parents -n1 "$c" | wc -w)" -eq 2 ] && picks="$picks $c"
	done
	if [ -z "$picks" ]; then
		note "- $label (\`${tip:0:7}\`): already in upstream, nothing to apply"
		echo "patch $label $tip merged" >> "$MAN"
		return 0
	fi
	if git cherry-pick $picks >/dev/null 2>&1; then
		note "- $label (\`${tip:0:7}\`): applied $(echo $picks | wc -w) commit(s)"
		echo "patch $label $tip applied" >> "$MAN"
	else
		git cherry-pick --abort || true
		note "- ⚠️ $label (\`${tip:0:7}\`): **conflicts with upstream, left out of this build**"
		echo "patch $label $tip conflict" >> "$MAN"
	fi
}

note "## What went in"
note
note "- upstream \`$UPSTREAM\` main at \`${UP:0:7}\`"

# 2. patch branches of a fork
if [ -n "${PATCH_FORK:-}" ]; then
	branches=${PATCH_FORK_BRANCHES:-auto}
	if [ "$branches" = auto ]; then
		git fetch --quiet "$(gh_url "$PATCH_FORK")" main
		branches=$(git show FETCH_HEAD:.github/workflows/weekly-upstream.yml 2>/dev/null \
			| sed -n 's/^ *PATCH_BRANCHES: *//p' | head -1)
	fi
	for br in $branches; do
		if git fetch --quiet "$(gh_url "$PATCH_FORK")" "$br" 2>/dev/null; then
			apply_fetched "$PATCH_FORK $br"
		else
			note "- $PATCH_FORK $br: branch gone (merged or dropped)"
			echo "patch $PATCH_FORK/$br gone" >> "$MAN"
		fi
	done
fi

# 3. upstream pull requests
for pr in ${UPSTREAM_PRS:-}; do
	if git fetch --quiet "$(gh_url "$UPSTREAM")" "refs/pull/$pr/head" 2>/dev/null; then
		apply_fetched "PR #$pr"
	else
		note "- PR #$pr: not found"
	fi
done

# 4. overlay files from this branch
for p in ${OVERLAY:-}; do
	if [ -d "$LOCAL/$p" ]; then
		mkdir -p "$p"; cp -r "$LOCAL/$p/." "$p/"
	elif [ -e "$p" ] && ! cmp -s "$LOCAL/$p" "$p"; then
		note "- \`$p\`: **upstream now ships its own version; using upstream's, check it**"
		echo "overlay $p upstream" >> "$MAN"; continue
	else
		cp "$LOCAL/$p" "$p"
	fi
	echo "overlay $p $(cd "$LOCAL" && find "$p" -type f -exec sha256sum {} + | sort | sha256sum | cut -c1-16)" >> "$MAN"
done
note "- this branch's configs and board files: $(echo ${OVERLAY:-none})"

# The build machinery itself travels with the tree, so the published branch
# can rebuild itself; upstream's own CI workflows are left out of it.
mkdir -p .github/edge .github/workflows
find .github/workflows -type f ! -name 'edge-firmware.yml' -delete
cp -r "$LOCAL/.github/edge/." .github/edge/
cp "$LOCAL/.github/workflows/edge-firmware.yml" .github/workflows/
git add -A >/dev/null
git commit -q -m "edge switches: configs, board files and build workflow [edge-sync]

Assembled from upstream ${UP:0:7}; see the release notes for the full list." || true

# Pull requests to keep an eye on (their head is part of the fingerprint, so a
# change produces a release whose notes say so)
for pr in ${WATCH_PRS:-}; do
	head=$(git ls-remote "$(gh_url "$UPSTREAM")" "refs/pull/$pr/head" | cut -f1)
	open=$(git ls-remote "$(gh_url "$UPSTREAM")" "refs/pull/$pr/merge" | cut -f1)
	echo "watch #$pr ${head:-none} ${open:+open}" >> "$MAN"
done

FP=$(sha256sum "$MAN" | cut -c1-16)
echo "$FP" > "$WORK/fingerprint"

# Compare with the last release
LAST_FP=""; LAST_UP=""; LAST_MAN=""
if [ -n "$GH" ] && [ -n "${GITHUB_REPOSITORY:-}" ]; then
	tag=$(gh release list -R "$GITHUB_REPOSITORY" --limit 30 --json tagName \
		--jq '[.[].tagName | select(startswith("fw-"))][0] // ""')
	if [ -n "$tag" ]; then
		body=$(gh release view "$tag" -R "$GITHUB_REPOSITORY" --json body --jq .body)
		LAST_FP=$(echo "$body" | sed -n 's/^fingerprint: *//p' | head -1)
		LAST_MAN=$(echo "$body" | sed -n '/^```manifest/,/^```$/p' | sed '1d;$d')
		LAST_UP=$(echo "$LAST_MAN" | awk '$1=="upstream"{print $3}')
	fi
fi
echo "$LAST_FP" > "$WORK/last_fingerprint"

note
note "## Changes since the last release"
note
if [ -z "$LAST_UP" ]; then
	note "First release of this kind."
else
	if [ "$LAST_UP" = "$UP" ]; then
		note "- upstream: unchanged"
	elif git merge-base --is-ancestor "$LAST_UP" "$UP" 2>/dev/null; then
		n=$(git rev-list --count --no-merges "$LAST_UP..$UP")
		note "- upstream: $n new commit(s)"
		note
		note '```'
		git log --no-merges --format='%h %s' "$LAST_UP..$UP" | head -40 >> "$NOTES"
		note '```'
		note
		changed=$(git diff --name-only "$LAST_UP" "$UP")
		# a switch's board files (following symlinks into machine/pcb/), plus
		# the upstream files a pinned/overlaid board was derived from
		for entry in ${SWITCHES:-} ${BOARD_WATCH:-}; do
			sw=${entry%%:*}; m=${entry#*:}
			files=""
			for f in "machine/$m.c" "machine/$m.h" "machine/${m}_init.c"; do
				files="$files $f"
				[ -L "$f" ] && files="$files machine/$(readlink "$f")"
			done
			hit=$(for f in $files; do echo "$changed" | grep -x "$f" || true; done | sort -u | tr '\n' ' ')
			[ -n "$hit" ] && note "- **$sw: upstream changed \`$m\` ($hit)** – check before updating $sw"
		done
	else
		note "- upstream: history rewritten since \`${LAST_UP:0:7}\`"
	fi
	# patch and watch-list differences
	diff <(echo "$LAST_MAN" | grep -E '^(patch|watch|overlay) ' | sort) \
	     <(grep -E '^(patch|watch|overlay) ' "$MAN" | sort) \
	     | sed -n 's/^> /- now: /p; s/^< /- was: /p' >> "$NOTES" || true
fi

{
	echo
	echo "fingerprint: $FP"
	echo
	echo '```manifest'
	cat "$MAN"
	echo '```'
} >> "$NOTES"

if [ "$FP" = "$LAST_FP" ]; then echo "unchanged"; else echo "changed"; fi > "$WORK/status"
cat "$WORK/status"

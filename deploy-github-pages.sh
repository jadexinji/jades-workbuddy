#!/usr/bin/env bash
set -euo pipefail

repo_name="${1:-jades-workbuddy}"

cd "$(dirname "$0")"

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI is not logged in. Run: gh auth login -h github.com"
  exit 1
fi

if [ ! -d .git ]; then
  git init -b main
fi

git add .
git commit -m "Deploy Jade's Workbuddy" >/dev/null 2>&1 || true

if ! git remote get-url origin >/dev/null 2>&1; then
  gh repo create "$repo_name" --public --source=. --remote=origin --push
else
  git push -u origin main
fi

owner_repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
gh api --method POST "repos/${owner_repo}/pages" \
  -f source[branch]=main \
  -f source[path]=/ >/dev/null 2>&1 || true

echo "Published. Open: https://$(gh api "repos/${owner_repo}/pages" -q .cname 2>/dev/null || true)"
echo "If no URL printed above, check GitHub repo Settings -> Pages."

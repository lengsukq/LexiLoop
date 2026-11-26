#!/usr/bin/env bash
set -euo pipefail

# Vercel Ignored Build Step (Root Directory = next-app):
# exit 0 -> 无 next-app 变更，跳过构建；exit 1 -> 存在变更或无法比对，继续构建。
if [ -n "${VERCEL_GIT_PREVIOUS_SHA:-}" ] && git cat-file -e "${VERCEL_GIT_PREVIOUS_SHA}^{commit}" 2>/dev/null; then
  git diff --quiet "${VERCEL_GIT_PREVIOUS_SHA}" HEAD -- .
  exit $?
fi

if git rev-parse --verify HEAD^ >/dev/null 2>&1; then
  git diff --quiet HEAD^ HEAD -- .
  exit $?
fi

exit 1

#!/bin/bash

total_commits=$(git rev-list --all --count)
echo "Total number of commits: $total_commits"

search_string="PythonEnvManager"

git log --all --pretty=format:"%H" | while read commit_hash; do
  commit_number=$(git rev-list --count "$commit_hash")
  matching_files=$(git grep -l "$search_string" "$commit_hash" -- apps/ lib/)
  if [[ ! -z "$matching_files" ]]; then
    echo "Commit $commit_hash (commit number: $commit_number) has files containing '$search_string':"
    while IFS= read -r file; do
      echo "  - $file"
    done <<< "$matching_files"
  fi
done

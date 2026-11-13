#!/usr/bin/env bash
# Lint changed files only; unit tests and secret scanning run on every invocation.
set -Eeuo pipefail

base_sha="${1:?Usage: ci-quality.sh <base-sha> <head-sha>}"
head_sha="${2:?Usage: ci-quality.sh <base-sha> <head-sha>}"

for sha in "$base_sha" "$head_sha"; do
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || {
    echo "::error::Invalid Git commit SHA supplied to the quality checks."
    exit 2
  }
done

mapfile -d '' changed_files < <(
  git diff --name-only --diff-filter=ACMR -z "$base_sha" "$head_sha"
)

nix_files=()
shell_files=()
python_files=()
workflow_changed=no

for path in "${changed_files[@]}"; do
  [[ -f "$path" ]] || continue
  case "$path" in
    *.nix) nix_files+=("$path") ;;
    *.sh) shell_files+=("$path") ;;
    *.py) python_files+=("$path") ;;
    .github/workflows/*.yml|.github/workflows/*.yaml)
      workflow_changed=yes
      ;;
  esac
done

failed=0

if (("${#nix_files[@]}" > 0)); then
  echo "::group::Nix formatting"
  for file in "${nix_files[@]}"; do
    if ! nixfmt < "$file" | diff -u "$file" -; then
      echo "::error file=$file::Nix file is not formatted with nixfmt."
      failed=1
    fi
  done
  echo "::endgroup::"

  echo "::group::Statix"
  for file in "${nix_files[@]}"; do
    if ! statix check "$file"; then
      failed=1
    fi
  done
  echo "::endgroup::"

  echo "::group::Dead Nix code"
  if ! deadnix --fail --no-lambda-arg --no-lambda-pattern-names "${nix_files[@]}"; then
    failed=1
  fi
  echo "::endgroup::"
else
  echo "No changed Nix files; Nix format and lint checks skipped."
fi

if (("${#shell_files[@]}" > 0)); then
  echo "::group::Bash syntax and ShellCheck"
  for file in "${shell_files[@]}"; do
    if ! bash -n "$file"; then
      failed=1
    fi
    if ! shfmt -d -i 2 "$file"; then
      failed=1
    fi
    if ! shellcheck --severity=warning "$file"; then
      failed=1
    fi
  done
  echo "::endgroup::"
else
  echo "No changed shell scripts; ShellCheck skipped."
fi

if (("${#python_files[@]}" > 0)); then
  echo "::group::Python lint and format"
  if ! ruff check --no-fix "${python_files[@]}"; then
    failed=1
  fi
  if ! ruff format --check "${python_files[@]}"; then
    failed=1
  fi
  echo "::endgroup::"
else
  echo "No changed Python files; Ruff skipped."
fi

if [[ "$workflow_changed" == yes ]]; then
  echo "::group::GitHub Actions workflow validation"
  if ! actionlint; then
    failed=1
  fi
  echo "::endgroup::"
else
  echo "No changed workflow files; actionlint skipped."
fi

echo "::group::Nori updater unit tests"
if ! python3 -m unittest discover -s tests -p 'test_*.py' -v; then
  failed=1
fi
echo "::endgroup::"

echo "::group::Secret scanning (redacted output)"
if ! gitleaks git --redact --no-banner --log-opts="$base_sha..$head_sha" .; then
  failed=1
fi
echo "::endgroup::"

if ((failed != 0)); then
  echo "::error::One or more quality or security checks failed."
  exit 1
fi

echo "All quality and security checks passed."

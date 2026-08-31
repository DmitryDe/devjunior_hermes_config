#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "ACTION_EXECUTION_PREFLIGHT=FAIL"
  echo "reason=$1"
  exit 1
}

pass() {
  echo "ACTION_EXECUTION_PREFLIGHT=PASS"
  echo "name=$1"
  echo "version=$2"
  echo "sha256=$3"
  exit 0
}

normalize_path() {
  local p="$1"
  local conv
  if command -v cygpath >/dev/null 2>&1; then
    conv="$(cygpath -m "$p" 2>/dev/null || true)"
    if [[ -n "${conv}" ]]; then
      p="${conv}"
    fi
  fi
  p="${p//\\//}"
  if [[ "${p}" =~ ^/mnt/([a-zA-Z])/(.*)$ ]]; then
    local wsl_drive
    wsl_drive="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')"
    p="${wsl_drive}:/${BASH_REMATCH[2]}"
  elif [[ "${p}" =~ ^/([a-zA-Z])/(.*)$ ]]; then
    local drive
    drive="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')"
    p="${drive}:/${BASH_REMATCH[2]}"
  fi
  p="${p%/}"
  printf '%s' "${p}"
}

paths_equal() {
  local a b
  a="$(normalize_path "$1")"
  b="$(normalize_path "$2")"
  [[ "${a}" == "${b}" ]] && return 0
  local al bl
  al="$(printf '%s' "${a}" | tr '[:upper:]' '[:lower:]')"
  bl="$(printf '%s' "${b}" | tr '[:upper:]' '[:lower:]')"
  [[ "${al}" == "${bl}" ]]
}

path_inside() {
  local child parent
  child="$(normalize_path "$1")"
  parent="$(normalize_path "$2")"
  [[ "${child}" == "${parent}" ]] && return 0
  [[ "${child}" == "${parent}/"* ]] && return 0
  local cl pl
  cl="$(printf '%s' "${child}" | tr '[:upper:]' '[:lower:]')"
  pl="$(printf '%s' "${parent}" | tr '[:upper:]' '[:lower:]')"
  [[ "${cl}" == "${pl}" ]] && return 0
  [[ "${cl}" == "${pl}/"* ]]
}

compute_package_sha256() {
  local dir="$1"
  (
    cd "${dir}" || exit 1
    find . -type f \
      ! -path './.git/*' \
      ! -path '*/__pycache__/*' \
      ! -name '*~' \
      ! -name '*.swp' \
      | sed 's|^\./||' \
      | LC_ALL=C sort \
      | while IFS= read -r rel; do
          [[ -n "${rel}" ]] || continue
          h="$(sha256sum "${rel}" | awk '{print $1}')"
          printf '%s  %s\n' "${h}" "${rel}"
        done \
      | sha256sum \
      | awk '{print $1}'
  )
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="${PROFILE_ROOT}"
LOCK_FILE="${PROFILE_ROOT}/skills.lock"
CONFIG_FILE="${PROFILE_ROOT}/config.yaml"

# 1. skills.lock exists and all four keys present
[[ -f "${LOCK_FILE}" ]] || fail lock_missing

LOCK_NAME=""
LOCK_VERSION=""
LOCK_RELATIVE_DIR=""
LOCK_SHA256=""
while IFS= read -r line || [[ -n "${line}" ]]; do
  line="${line%$'\r'}"
  [[ -z "${line}" ]] && continue
  case "${line}" in
    ACTION_EXECUTION_NAME=*) LOCK_NAME="${line#ACTION_EXECUTION_NAME=}" ;;
    ACTION_EXECUTION_VERSION=*) LOCK_VERSION="${line#ACTION_EXECUTION_VERSION=}" ;;
    ACTION_EXECUTION_RELATIVE_DIR=*) LOCK_RELATIVE_DIR="${line#ACTION_EXECUTION_RELATIVE_DIR=}" ;;
    ACTION_EXECUTION_PACKAGE_SHA256=*) LOCK_SHA256="${line#ACTION_EXECUTION_PACKAGE_SHA256=}" ;;
  esac
done < "${LOCK_FILE}"

[[ -n "${LOCK_NAME}" && -n "${LOCK_VERSION}" && -n "${LOCK_RELATIVE_DIR}" && -n "${LOCK_SHA256}" ]] \
  || fail lock_incomplete

# 2. canonical package path resolves inside REPO_ROOT
case "${LOCK_RELATIVE_DIR}" in
  *..*) fail package_outside_repo ;;
  /*) fail package_outside_repo ;;
esac

PACKAGE_DIR="${PROFILE_ROOT}/${LOCK_RELATIVE_DIR}"
[[ -d "${PACKAGE_DIR}" ]] || fail package_outside_repo
path_inside "${PACKAGE_DIR}" "${REPO_ROOT}" || fail package_outside_repo

# 3. required three skill files exist
SKILL_MD="${PACKAGE_DIR}/SKILL.md"
WORKFLOW_MD="${PACKAGE_DIR}/references/workflow.md"
INVARIANTS_MD="${PACKAGE_DIR}/references/invariants.md"
[[ -f "${SKILL_MD}" && -f "${WORKFLOW_MD}" && -f "${INVARIANTS_MD}" ]] \
  || fail skill_files_missing

# 4. SKILL.md exact name/version match lock
FRONT_NAME="$(grep -E '^name:[[:space:]]*' "${SKILL_MD}" | head -n1 | sed 's/^name:[[:space:]]*//;s/[[:space:]]*$//')"
FRONT_VERSION="$(grep -E '^version:[[:space:]]*' "${SKILL_MD}" | head -n1 | sed 's/^version:[[:space:]]*//;s/[[:space:]]*$//')"
[[ "${FRONT_NAME}" == "${LOCK_NAME}" ]] || fail name_mismatch
[[ "${FRONT_VERSION}" == "${LOCK_VERSION}" ]] || fail version_mismatch

# 5. package hash exact match
ACTUAL_SHA256="$(compute_package_sha256 "${PACKAGE_DIR}")"
[[ "${ACTUAL_SHA256}" == "${LOCK_SHA256}" ]] || fail hash_mismatch

# 7. skills.project_discovery in config is false
[[ -f "${CONFIG_FILE}" ]] || fail project_discovery_enabled
PROJECT_DISCOVERY="$(
  awk '
    /^skills:[[:space:]]*$/ { in_skills=1; next }
    in_skills && /^[^[:space:]]/ { in_skills=0 }
    in_skills && /^[[:space:]]*project_discovery:[[:space:]]*/ {
      val=$0
      sub(/^[[:space:]]*project_discovery:[[:space:]]*/, "", val)
      gsub(/[[:space:]]/, "", val)
      print val
      exit
    }
  ' "${CONFIG_FILE}"
)"
[[ "${PROJECT_DISCOVERY}" == "false" ]] || fail project_discovery_enabled

# 8. canonical skills root in external_dirs if package is not a direct profile-local skill
PROFILE_LOCAL_DIRECT="${PROFILE_ROOT}/skills/${LOCK_NAME}"
if ! paths_equal "${PACKAGE_DIR}" "${PROFILE_LOCAL_DIRECT}"; then
  CANONICAL_SKILLS_ROOT="$(cd "${PACKAGE_DIR}/../.." && pwd)"
  FOUND_EXTERNAL=0
  while IFS= read -r ed_path; do
    [[ -z "${ed_path}" ]] && continue
    if paths_equal "${ed_path}" "${CANONICAL_SKILLS_ROOT}"; then
      FOUND_EXTERNAL=1
      break
    fi
  done < <(
    awk '
      /^skills:[[:space:]]*$/ { in_skills=1; next }
      in_skills && /^[^[:space:]]/ { in_skills=0; in_ed=0 }
      in_skills && /^[[:space:]]*external_dirs:[[:space:]]*$/ { in_ed=1; next }
      in_ed && /^[[:space:]]*-[[:space:]]*/ {
        val=$0
        sub(/^[[:space:]]*-[[:space:]]*/, "", val)
        gsub(/[[:space:]]+$/, "", val)
        print val
        next
      }
      in_ed { in_ed=0 }
    ' "${CONFIG_FILE}"
  )
  [[ "${FOUND_EXTERNAL}" -eq 1 ]] || fail external_dir_missing
fi

# 9. no higher-precedence duplicate action-execution outside the canonical package
if [[ -d "${PROFILE_ROOT}/skills" ]]; then
  while IFS= read -r other_skill; do
    [[ -z "${other_skill}" ]] && continue
    other_dir="$(dirname "${other_skill}")"
    if paths_equal "${other_dir}" "${PACKAGE_DIR}"; then
      continue
    fi
    if grep -Eq '^name:[[:space:]]*action-execution[[:space:]]*$' "${other_skill}"; then
      fail duplicate_skill_shadowing
    fi
  done < <(find "${PROFILE_ROOT}/skills" -type f -name SKILL.md)
fi

# 6. hermes -p devjunior skills list contains action-execution
# (after static checks 7-9 so a missing local Hermes still proves repo integrity)
if ! command -v hermes >/dev/null 2>&1; then
  fail hermes_not_found
fi
HERMES_LIST="$(hermes -p devjunior skills list 2>/dev/null || true)"
printf '%s\n' "${HERMES_LIST}" | grep -Eq '(^|[[:space:]/])action-execution([[:space:]]|$)' \
  || fail skill_not_visible

# 10. this script never auto-fixes configuration or skill files
pass "${LOCK_NAME}" "${LOCK_VERSION}" "${ACTUAL_SHA256}"

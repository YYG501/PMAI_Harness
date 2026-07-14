#!/usr/bin/env bash
# Guardrails for running PMAI skills before a project is initialized.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

is_project_skill() {
  case "$1" in
    init-project|pmai-upgrade) return 1 ;;
    *) return 0 ;;
  esac
}

test_project_skills_guard_uninitialized_repos() {
  start_test "project skills stop on uninitialized PMAI repo"

  local skill_file skill_name missing=0
  for skill_file in "$REPO_ROOT"/skills/*/SKILL.md; do
    skill_name=$(basename "$(dirname "$skill_file")")
    is_project_skill "$skill_name" || continue

    if ! grep -q 'skill-preamble.sh' "$skill_file"; then
      echo "missing preamble: $skill_name" >&2
      missing=1
    fi
    if ! grep -q 'PMAI_PROJECT_INITIALIZED: 0' "$skill_file"; then
      echo "missing initialized guard: $skill_name" >&2
      missing=1
    fi
    if ! grep -q '/pmai-init-project' "$skill_file"; then
      echo "missing init guidance: $skill_name" >&2
      missing=1
    fi
  done

  if [ "$missing" != "0" ]; then
    _fail "some public project skills do not guard uninitialized repos"
    return
  fi
  pass_test
}

test_allowed_entrypoint_exceptions_are_explicit() {
  start_test "init-project / upgrade remain explicit exceptions"

  if grep -q 'PMAI_PROJECT_INITIALIZED: 0' "$REPO_ROOT/skills/init-project/SKILL.md"; then
    _fail "init-project should be able to run before PMAI initialization"
    return
  fi
  if grep -q 'PMAI_PROJECT_INITIALIZED: 0' "$REPO_ROOT/skills/pmai-upgrade/SKILL.md"; then
    _fail "pmai-upgrade should not depend on consumer repo initialization"
    return
  fi
  if ! grep -q '仓外文件' "$REPO_ROOT/skills/humanize/SKILL.md" \
     || ! grep -q '不写 PMAI 项目产物' "$REPO_ROOT/skills/humanize/SKILL.md"; then
    _fail "humanize should document its narrow non-project exception"
    return
  fi
  pass_test
}

test_opencode_command_template_guards_uninitialized_repos() {
  start_test "OpenCode command template runs preamble before project skills"

  local file="$REPO_ROOT/scripts/install-opencode-commands.sh"
  assert_file_contains "$file" 'AGENTS.md' "OpenCode command should read project AGENTS entry" || return
  assert_file_contains "$file" 'skill-preamble.sh' "OpenCode command should run PMAI preamble" || return
  assert_file_contains "$file" 'PMAI_PROJECT_INITIALIZED: 0' "OpenCode command should stop uninitialized projects" || return
  assert_file_contains "$file" '/pmai-init-project' "OpenCode command should guide initialization" || return
  pass_test
}

test_project_skills_guard_uninitialized_repos
test_allowed_entrypoint_exceptions_are_explicit
test_opencode_command_template_guards_uninitialized_repos

report_results "skill-init-guard"

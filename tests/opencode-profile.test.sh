#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${repo_root}/opencode-profile"

tmpdir="$(mktemp -d)"
home="${tmpdir}/home"
fakebin="${tmpdir}/bin"

cleanup() {
  rm -rf "${tmpdir}"
}
trap cleanup EXIT

mkdir -p "${home}" "${fakebin}"

cat > "${fakebin}/pgrep" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "${fakebin}/pgrep"

PATH="${fakebin}:${PATH}"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

reset_home() {
  rm -rf "${home}"
  mkdir -p "${home}"
}

auth_dir() {
  printf '%s/.local/share/opencode' "${home}"
}

profiles_dir() {
  printf '%s/profiles' "$(auth_dir)"
}

run_script() {
  local cwd="${1:-${repo_root}}"
  shift || true

  set +e
  output="$(
    cd "${cwd}" && HOME="${home}" PATH="${PATH}" "${script}" "$@" 2>&1
  )"
  status=$?
  set -e
}

assert_ok() {
  [[ "${status}" -eq 0 ]] || fail "expected success, got exit ${status}: ${output}"
}

assert_fail() {
  [[ "${status}" -ne 0 ]] || fail "expected failure, got exit 0: ${output}"
}

assert_output_contains() {
  [[ "${output}" == *"$1"* ]] || fail "expected output to contain: $1\nActual: ${output}"
}

assert_file_contains() {
  local file="$1"
  local expected="$2"
  [[ -f "${file}" ]] || fail "expected file to exist: ${file}"
  [[ "$(cat "${file}")" == "${expected}" ]] || fail "unexpected file contents for ${file}"
}

assert_symlink_target() {
  local file="$1"
  local expected="$2"
  [[ -L "${file}" ]] || fail "expected symlink: ${file}"
  [[ "$(readlink "${file}")" == "${expected}" ]] || fail "unexpected symlink target for ${file}"
}

test_make_empty() {
  reset_home

  run_script "${repo_root}" make empty
  assert_ok
  assert_file_contains "$(profiles_dir)/empty.json" '{}'
  [[ ! -e "$(auth_dir)/auth.json" ]] || fail "did not expect auth.json to exist after make <name>"
  assert_output_contains "opencode-profile switch empty"
}

test_regular_auth_make_current_and_which() {
  reset_home
  mkdir -p "$(auth_dir)"
  printf '%s' '{"token":"abc"}' > "$(auth_dir)/auth.json"

  run_script "${repo_root}" which
  assert_ok
  assert_output_contains 'auth.json is a regular file (no profile active).'

  run_script "${repo_root}" make current --current
  assert_ok
  assert_file_contains "$(profiles_dir)/current.json" '{"token":"abc"}'
  assert_symlink_target "$(auth_dir)/auth.json" "${home}/.local/share/opencode/profiles/current.json"

  run_script "${repo_root}" which
  assert_ok
  [[ "${output}" == "current" ]] || fail "expected which to print current, got: ${output}"
}

test_switch_list_rename() {
  reset_home

  run_script "${repo_root}" make work
  assert_ok
  run_script "${repo_root}" make personal
  assert_ok
  run_script "${repo_root}" switch work
  assert_ok
  assert_symlink_target "$(auth_dir)/auth.json" "${home}/.local/share/opencode/profiles/work.json"

  run_script "${repo_root}" list
  assert_ok
  assert_output_contains 'OpenAI profiles:'
  assert_output_contains 'work'
  assert_output_contains 'personal'
  assert_output_contains '(active)'

  run_script "${repo_root}" which
  assert_ok
  [[ "${output}" == "work" ]] || fail "expected which to print work, got: ${output}"

  run_script "${repo_root}" rename work office
  assert_ok
  assert_file_contains "$(profiles_dir)/office.json" '{}'
  [[ ! -e "$(profiles_dir)/work.json" ]] || fail "expected old profile file to be renamed"
  assert_symlink_target "$(auth_dir)/auth.json" "${home}/.local/share/opencode/profiles/office.json"

  run_script "${repo_root}" list
  assert_ok
  assert_output_contains 'office'
  assert_output_contains '(active)'
}

test_delete_safety() {
  reset_home
  mkdir -p "$(auth_dir)"
  printf '%s' '{"token":"seed"}' > "$(auth_dir)/auth.json"

  run_script "${repo_root}" make lone --current
  assert_ok

  run_script "${repo_root}" delete lone
  assert_fail
  assert_output_contains 'cannot delete the last profile'

  run_script "${repo_root}" make spare
  assert_ok

  run_script "${repo_root}" delete lone
  assert_fail
  assert_output_contains 'cannot delete the active profile'

  run_script "${repo_root}" switch spare
  assert_ok

  run_script "${repo_root}" delete lone
  assert_ok
  [[ ! -e "$(profiles_dir)/lone.json" ]] || fail "expected lone profile to be deleted"

  run_script "${repo_root}" delete spare
  assert_fail
  assert_output_contains 'cannot delete the last profile'
}

test_duplicate_and_invalid_name() {
  reset_home

  run_script "${repo_root}" make dup
  assert_ok

  run_script "${repo_root}" make dup
  assert_fail
  assert_output_contains "profile 'dup' already exists"

  run_script "${repo_root}" make bad/name
  assert_fail
  assert_output_contains "invalid profile name 'bad/name'"
}

test_second_account_writes_to_switched_profile() {
  reset_home
  mkdir -p "$(auth_dir)"
  printf '%s' '{"token":"first"}' > "$(auth_dir)/auth.json"

  run_script "${repo_root}" make codex-1 --current
  assert_ok
  assert_file_contains "$(profiles_dir)/codex-1.json" '{"token":"first"}'

  run_script "${repo_root}" make codex-2
  assert_ok
  run_script "${repo_root}" switch codex-2
  assert_ok

  printf '%s' '{"token":"second"}' > "$(auth_dir)/auth.json"
  assert_file_contains "$(profiles_dir)/codex-1.json" '{"token":"first"}'
  assert_file_contains "$(profiles_dir)/codex-2.json" '{"token":"second"}'
}

test_managed_symlink_make_current_is_refused() {
  reset_home
  mkdir -p "$(auth_dir)/profiles"
  printf '%s' '{"token":"seed"}' > "$(auth_dir)/profiles/source.json"
  ln -s profiles/source.json "$(auth_dir)/auth.json"

  run_script "$(auth_dir)" make relative --current
  assert_fail
  assert_output_contains "auth.json is already managed by profile 'source'"
  [[ ! -e "$(profiles_dir)/relative.json" ]] || fail "did not expect duplicate profile to be created"
}

tests=(
  test_make_empty
  test_regular_auth_make_current_and_which
  test_switch_list_rename
  test_delete_safety
  test_duplicate_and_invalid_name
  test_second_account_writes_to_switched_profile
  test_managed_symlink_make_current_is_refused
)

for test in "${tests[@]}"; do
  "$test"
  printf 'ok - %s\n' "${test}"
done

printf 'all tests passed\n'

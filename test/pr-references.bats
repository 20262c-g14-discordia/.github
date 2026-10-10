setup() {
  bats_require_minimum_version 1.5.0
  CHECK=$BATS_TEST_DIRNAME/../actions/pr-references/pr-references.sh
}

check() { # BODY -- run the check against BODY
  PR_BODY=$1 run "$CHECK"
}

# The two fixtures are real merged PRs whose bare `Ref` left a finished issue In Progress
# for weeks: discordia-messaging#12 (DIS-107) and meta#20 (DIS-67).
@test "a bare Ref fails and names the issue: discordia-messaging#12" {
  check "$(cat "$BATS_TEST_DIRNAME/fixtures/messaging-12.md")"
  [ "$status" -eq 1 ]
  [[ $output == *"::error title=Ref DIS-107::"* ]]
  [[ $output == *"change the line to 'Closes DIS-107'"* ]]
}

@test "a bare Ref fails and names the issue: meta#20" {
  check "$(cat "$BATS_TEST_DIRNAME/fixtures/meta-20.md")"
  [ "$status" -eq 1 ]
  [[ $output == *"::error title=Ref DIS-67::"* ]]
}

@test "Closes passes" {
  check $'Closes DIS-107\n\n## Why\n\nIt finishes the issue.'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Ref passes when Still open says what stays unmet" {
  check $'Ref DIS-87\n\n## Still open\n\n- DIS-87: DIS-93 and DIS-99 are open.\n\n## Out of scope\n\nnone'
  [ "$status" -eq 0 ]
}

@test "a Still open bullet with no reason fails" {
  check $'Ref DIS-87\n\n## Still open\n\n- DIS-87'
  [ "$status" -eq 1 ]
}

@test "a reason outside Still open does not count" {
  check $'Ref DIS-87\n\n## Out of scope\n\n- DIS-87: the web half.'
  [ "$status" -eq 1 ]
}

@test "every issue after a non-closing word needs its own reason" {
  check $'Part of DIS-12, DIS-13 and DIS-14\n\n## Still open\n\n- DIS-12: CA 3.\n- DIS-14: CA 1.'
  [ "$status" -eq 1 ]
  [[ $output == *"title=Ref DIS-13::"* ]]
  [[ $output != *"title=Ref DIS-12::"* ]]
  [[ $output != *"title=Ref DIS-14::"* ]]
}

@test "DIS-1's reason is not DIS-12's" {
  check $'Ref DIS-1\n\n## Still open\n\n- DIS-12: CA 3.'
  [ "$status" -eq 1 ]
}

@test "the template's own comments are not references" {
  check $'<!--\nRef DIS-5\n-->\nCloses DIS-6'
  [ "$status" -eq 0 ]
}

@test "a relation word links without a reason" {
  check 'Related to DIS-12'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no reference warns and passes" {
  check $'## Why\n\nNothing in the backlog fits; this fixes a typo.'
  [ "$status" -eq 0 ]
  [[ $output == "::warning title=Linear issue::"* ]]
}

@test "CRLF bodies, as GitHub sends them, parse" {
  check $'Ref DIS-87\r\n\r\n## Still open\r\n\r\n- DIS-87: the web half.\r\n'
  [ "$status" -eq 0 ]
}

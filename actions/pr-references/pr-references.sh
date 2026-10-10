#!/usr/bin/env bash
# Checks the Linear references in a PR body (PR_BODY). See action.yml.
set -euo pipefail

# Linear's magic words, from https://linear.app/docs/github#magic-words.
closing='close|closes|closed|closing|fix|fixes|fixed|fixing|resolve|resolves|resolved|resolving|complete|completes|completed|completing|implement|implements|implemented|implementing'
non_closing='ref|refs|references|part of|contributes to|toward|towards'
relation='relates to|related to'

# HTML comments are the template's instructions, not the author's references.
body=$(printf '%s\n' "${PR_BODY:-}" | tr -d '\r' | perl -0pe 's/<!--.*?-->//gs')

if ! grep -Eiq "^($closing|$non_closing|$relation) DIS-[0-9]+" <<<"$body"; then
  echo "::warning title=Linear issue::no line like 'Closes DIS-12' or 'Ref DIS-12', so Linear will not link this PR. The brief asks every PR to reference the story or task behind it. Add one, or state in the body that no issue originated this work."
  exit 0
fi

still_open=$(awk 'tolower($0) ~ /^## still open[[:space:]]*$/ { on = 1; next } /^## / { on = 0 } on' <<<"$body")

failed=0
while read -r id; do
  [ -n "$id" ] || continue
  if ! grep -Eq "^[[:space:]]*[-*][[:space:]]+${id}[^0-9[:alnum:]]+[[:alnum:]]" <<<"$still_open"; then
    echo "::error title=Ref ${id}::${id} is referenced but not closed, and '## Still open' does not say why. Read ${id}'s acceptance criteria. If this PR, with what is already merged, meets every one, change the line to 'Closes ${id}'. Otherwise add '- ${id}: <the criteria still unmet>' under '## Still open'."
    failed=1
  fi
done < <(grep -Ei "^($non_closing) DIS-[0-9]+" <<<"$body" | grep -Eo 'DIS-[0-9]+' | sort -u)

exit "$failed"

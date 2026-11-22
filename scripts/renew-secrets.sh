#!/usr/bin/env bash
# Interactive walkthrough for renewing the secrets used by the Terraform
# workflow. Every step explains what to do, then waits for you.
#
#   scripts/renew-secrets.sh            # menu
#   scripts/renew-secrets.sh tf         # TF_API_TOKEN (Actions + Dependabot)
#   scripts/renew-secrets.sh slack      # SLACK_WEBHOOK_URL
#   scripts/renew-secrets.sh influx     # INFLUXDB_TOKEN (Terraform Cloud workspace)
#
# Secret values are read without echo and passed to gh on stdin; they are
# never printed, written to disk or put on a command line.
# Background: docs/terraform-workflow.md

set -euo pipefail

TFC_ORG="mygermanium"
TFC_WORKSPACE="influxdb-cloud"
TFC_TOKEN_NAME="gh-influxdb-cloud"
INFLUX_URL="https://westeurope-1.azure.cloud2.influxdata.com"
WORKFLOW="terraform.yml"

# ---------- output helpers ----------
if [[ -t 1 ]]; then
  B=$'\e[1m'; DIM=$'\e[2m'; C=$'\e[36m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; N=$'\e[0m'
else
  B=""; DIM=""; C=""; G=""; Y=""; R=""; N=""
fi

STEP=0
TOTAL=0

title() { printf '\n%s══ %s ══%s\n' "$B$C" "$1" "$N"; }
step() { STEP=$((STEP + 1)); printf '\n%s[Step %d/%d] %s%s\n' "$B" "$STEP" "$TOTAL" "$1" "$N"; }
help() { printf '%s  ℹ %s%s\n' "$DIM" "$1" "$N"; }
do_() { printf '  %s→%s %s\n' "$C" "$N" "$1"; }
ok() { printf '  %s✔ %s%s\n' "$G" "$1" "$N"; }
warn() { printf '  %s⚠ %s%s\n' "$Y" "$1" "$N"; }
fail() { printf '  %s✖ %s%s\n' "$R" "$1" "$N"; }
die() { fail "$1"; exit 1; }

pause() { read -rp "  ${DIM}Press Enter when done (Ctrl+C to abort)…${N} " _; }

confirm() { # confirm "question" [default y|n]
  local ans def="${2:-y}" hint="[Y/n]"
  [[ $def == n ]] && hint="[y/N]"
  read -rp "  $1 $hint " ans
  ans="${ans:-$def}"
  [[ $ans =~ ^[Yy] ]]
}

read_secret() { # read_secret VAR "prompt"  (no echo)
  local _v
  while true; do
    read -rsp "  $2: " _v; echo
    [[ -n $_v ]] && break
    warn "Empty value, paste it again."
  done
  printf -v "$1" '%s' "$_v"
}

open_url() {
  do_ "Open: ${B}$1${N}"
  if command -v wslview >/dev/null; then wslview "$1" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null; then xdg-open "$1" >/dev/null 2>&1 || true
  elif command -v open >/dev/null; then open "$1" >/dev/null 2>&1 || true
  fi
}

# ---------- preflight ----------
preflight() {
  command -v gh >/dev/null || die "gh (GitHub CLI) is not installed."
  command -v curl >/dev/null || die "curl is not installed."
  gh auth status >/dev/null 2>&1 || die "gh is not logged in. Run: gh auth login"
  REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) \
    || die "Run this from inside the influxdb-cloud repo."
  ok "GitHub repo: $REPO"
}

# ---------- verification via the drift check ----------
verify_with_drift_check() {
  step "Verify with a drift check"
  help "A drift-check run uses TF_API_TOKEN to reach Terraform Cloud, which uses"
  help "INFLUXDB_TOKEN to read InfluxDB. Green = both work. It never applies anything."
  help "If there is drift, the run is red and Slack gets a message (that also proves"
  help "SLACK_WEBHOOK_URL works)."
  if ! confirm "Start the drift check now?"; then
    warn "Skipped. Run later: gh workflow run $WORKFLOW -f drift_check=true"
    return
  fi
  gh workflow run "$WORKFLOW" -f drift_check=true >/dev/null
  do_ "Started, waiting for the run to appear…"
  local id="" i
  for i in {1..15}; do
    sleep 2
    id=$(gh run list --workflow "$WORKFLOW" --event workflow_dispatch --limit 1 \
      --json databaseId,createdAt --jq '.[0].databaseId') && [[ -n $id ]] && break
  done
  [[ -n $id ]] || { warn "Could not find the run; check the Actions tab."; return; }
  do_ "Run: https://github.com/$REPO/actions/runs/$id"
  help "If another Terraform run is in progress, this one queues behind it."
  if gh run watch "$id" --exit-status >/dev/null 2>&1; then
    ok "Drift check passed: credentials work and there is no drift."
  else
    fail "Drift check failed. Open the run link above and look at the 'Plan' step:"
    help "'unauthorized' / '401' → the token just set is wrong; run this script again."
    help "Plan shows changes → credentials are fine, the infra has drifted."
  fi
}

# ---------- TF_API_TOKEN ----------
renew_tf() {
  title "Renew TF_API_TOKEN (Terraform Cloud user token)"
  help "GitHub Actions uses this token to log in to Terraform Cloud for every plan,"
  help "apply and drift check. It is stored twice in GitHub: in the Actions secrets and"
  help "in the Dependabot secrets (Dependabot PRs cannot read Actions secrets)."
  STEP=0; TOTAL=6

  step "Create a new token in Terraform Cloud"
  help "Create a user token (not an organization token: that one can't run plans)."
  open_url "https://app.terraform.io/app/settings/tokens"
  do_ "Click ${B}Create an API token${N}"
  do_ "Description: ${B}$TFC_TOKEN_NAME${N}"
  do_ "Expiration: ${B}Custom${N}, about 1 year from today; write the date down"
  do_ "Click ${B}Generate token${N} and copy it (it is shown only once)"
  pause

  step "Paste the new token"
  help "Input is hidden. The token is checked against Terraform Cloud before saving."
  local token
  while true; do
    read_secret token "Terraform Cloud token"
    if curl -fsS -o /dev/null -H "Authorization: Bearer $token" \
      https://app.terraform.io/api/v2/account/details; then
      ok "Token is valid."
      break
    fi
    fail "Terraform Cloud rejected this token. Copy it again (whole value)."
  done

  step "Save it as the Actions secret"
  help "Used by the plan, plan-main, apply and drift jobs."
  printf '%s' "$token" | gh secret set TF_API_TOKEN --repo "$REPO" >/dev/null
  ok "Actions secret TF_API_TOKEN updated."

  step "Save it as the Dependabot secret"
  help "Used by the plan job on pull requests opened by Dependabot."
  printf '%s' "$token" | gh secret set TF_API_TOKEN --app dependabot --repo "$REPO" >/dev/null
  ok "Dependabot secret TF_API_TOKEN updated."
  unset token

  verify_with_drift_check

  step "Clean up and record the new expiry"
  help "Only delete the old token once the drift check above passed."
  open_url "https://app.terraform.io/app/settings/tokens"
  do_ "Delete the ${B}old${N} $TFC_TOKEN_NAME token (the one with the earlier expiry)"
  do_ "Update the expiry date in ${B}docs/terraform-workflow.md${N} (branch + PR; main is protected)"
  do_ "Add a calendar reminder ~2 weeks before the new expiry"
  pause
  ok "TF_API_TOKEN renewed."
}

# ---------- SLACK_WEBHOOK_URL ----------
renew_slack() {
  title "Renew SLACK_WEBHOOK_URL (Slack incoming webhook)"
  help "The daily drift check posts to this webhook on drift or errors. Webhooks don't"
  help "expire; renew when it leaked, the channel changed or the app was reinstalled."
  STEP=0; TOTAL=5

  step "Create a new webhook in Slack"
  open_url "https://api.slack.com/apps"
  do_ "Open the ${B}Terraform Drift${N} app → ${B}Incoming Webhooks${N}"
  do_ "Click ${B}Add New Webhook to Workspace${N}, pick the alerts channel, click ${B}Allow${N}"
  do_ "Copy the new URL (https://hooks.slack.com/services/…)"
  pause

  step "Paste the webhook URL"
  help "Input is hidden. The URL is a credential: anyone with it can post to the channel."
  local url
  while true; do
    read_secret url "Webhook URL"
    [[ $url == https://hooks.slack.com/* ]] && break
    fail "That doesn't look like a Slack webhook URL (https://hooks.slack.com/…)."
  done

  step "Send a test message (optional)"
  help "Posts a short test message to the channel to prove the URL works."
  if confirm "Send a test message?"; then
    if printf '{"text":":white_check_mark: Test from renew-secrets.sh (%s)"}' "$REPO" \
      | curl -fsS -o /dev/null -X POST -H 'Content-Type: application/json' --data @- "$url"; then
      ok "Slack accepted the message; check the channel."
    else
      fail "Slack rejected the request. Check the URL and run this step again."
      unset url; return 1
    fi
  fi

  step "Save it as the Actions secret"
  printf '%s' "$url" | gh secret set SLACK_WEBHOOK_URL --repo "$REPO" >/dev/null
  unset url
  ok "Actions secret SLACK_WEBHOOK_URL updated."

  step "Remove the old webhook"
  help "Do this so the old URL can't be used any more."
  do_ "In the same Incoming Webhooks page, click ${B}Remove${N} next to the old webhook"
  do_ "If other repos used the old URL, update their SLACK_WEBHOOK_URL too"
  pause
  ok "SLACK_WEBHOOK_URL renewed."
}

# ---------- INFLUXDB_TOKEN ----------
renew_influx() {
  title "Renew INFLUXDB_TOKEN (InfluxDB Cloud All Access token)"
  help "Terraform uses this token inside Terraform Cloud runs to manage buckets and"
  help "tokens. It is NOT a GitHub secret: it lives as a sensitive environment variable"
  help "in the Terraform Cloud workspace $TFC_ORG/$TFC_WORKSPACE."
  STEP=0; TOTAL=5

  step "Create a new All Access token in InfluxDB Cloud"
  open_url "$INFLUX_URL"
  do_ "${B}Load Data → API Tokens → Generate API Token → All Access API Token${N}"
  do_ "Description e.g. ${B}terraform-$(date +%Y%m%d)${N}, click ${B}Save${N}, copy the token"
  pause

  step "Check the new token (optional)"
  help "Calls the InfluxDB API with the token, without printing it."
  if confirm "Check the token now?"; then
    local itoken
    read_secret itoken "InfluxDB token"
    if curl -fsS -o /dev/null -H "Authorization: Token $itoken" "$INFLUX_URL/api/v2/orgs"; then
      ok "InfluxDB accepted the token."
    else
      fail "InfluxDB rejected the token; copy it again before continuing."
    fi
    unset itoken
  fi

  step "Put it in the Terraform Cloud workspace"
  help "Replace the value of the existing variable; keep it an environment variable."
  open_url "https://app.terraform.io/app/$TFC_ORG/workspaces/$TFC_WORKSPACE/variables"
  do_ "Find ${B}INFLUXDB_TOKEN${N} (category: env) → ${B}⋯ → Edit${N}"
  do_ "Paste the new token, keep ${B}Sensitive${N} checked, click ${B}Save variable${N}"
  pause

  verify_with_drift_check

  step "Delete the old token in InfluxDB Cloud"
  help "Only after the drift check passed. Do not delete the per-app tokens managed by"
  help "Terraform (telegraf, temp-monitor, dashboards); only the old All Access token."
  open_url "$INFLUX_URL"
  do_ "${B}Load Data → API Tokens${N} → delete the previous All Access token used by Terraform"
  pause
  ok "INFLUXDB_TOKEN renewed."
}

# ---------- main ----------
main() {
  title "Secret renewal for the Terraform workflow"
  help "Details: docs/terraform-workflow.md (section 'Secrets')."
  preflight

  local choice="${1:-}"
  if [[ -z $choice ]]; then
    printf '\n  Which secret do you want to renew?\n'
    printf '    1) TF_API_TOKEN       Terraform Cloud token (Actions + Dependabot), expires yearly\n'
    printf '    2) SLACK_WEBHOOK_URL  Slack webhook for drift alerts, no expiry\n'
    printf '    3) INFLUXDB_TOKEN     InfluxDB token in the Terraform Cloud workspace, no expiry\n'
    printf '    q) Quit\n'
    read -rp "  Choice: " choice
  fi

  case "$choice" in
    1|tf|TF_API_TOKEN) renew_tf ;;
    2|slack|SLACK_WEBHOOK_URL) renew_slack ;;
    3|influx|INFLUXDB_TOKEN) renew_influx ;;
    q|Q) exit 0 ;;
    *) die "Unknown choice: $choice" ;;
  esac
}

main "$@"

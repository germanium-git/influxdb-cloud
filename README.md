# influxdb-cloud

Terraform for the germanium InfluxDB Cloud 2 (TSM) organization: buckets and
per-writer API tokens. Replaces the self-hosted InfluxDB on `apollo`
(`germanium-git/temp-monitor`).

| Bucket | Written by | Data |
|:--|:--|:--|
| `Network` | telegraf (`germanium-git/argocd`, `apps/telegraf`) | SNMP `ifXTable` from SRX300 and the Dell switch, RUT240 LTE stats |
| `Temperature` | temp-monitor sensors | temperatures |

Retention is 30 days for both (the Free plan maximum; `retention_days`).

## What Terraform creates

- `influxdb_bucket.this["network"|"temperature"]`, protected with `prevent_destroy`
- `influxdb_authorization.writer["telegraf"]`: write-only, `Network`
- `influxdb_authorization.writer["temp-monitor"]`: write-only, `Temperature`
- `influxdb_authorization.reader`: read-only on both buckets, for dashboards

## Setup

InfluxDB Cloud: `https://westeurope-1.azure.cloud2.influxdata.com`, organization ID
`15297d32235a99a0` (both set as variable defaults).

1. **[InfluxDB Cloud UI](https://westeurope-1.azure.cloud2.influxdata.com)**: create an
   **All Access API token** for Terraform
   (Load Data → API Tokens → Generate API Token → All Access API Token).
2. **Terraform Cloud** workspace
   [`mygermanium/influxdb-cloud`](https://app.terraform.io/app/mygermanium/workspaces/influxdb-cloud)
   (created by the first `terraform init`) →
   [Variables](https://app.terraform.io/app/mygermanium/workspaces/influxdb-cloud/variables) →
   add an **Environment variable** `INFLUXDB_TOKEN` with that token, marked **Sensitive**.
3. Read the per-app InfluxDB tokens Terraform created (write-only tokens for Telegraf
   and temp-monitor, read-only token for dashboards). The values are kept in the
   Terraform Cloud state and marked sensitive, so read them locally:
   ```sh
   terraform init
   terraform output -json writer_tokens | jq -r .telegraf
   terraform output -json writer_tokens | jq -r '."temp-monitor"'
   terraform output -raw reader_token
   ```

## CI (GitHub Actions)

`.github/workflows/terraform.yml`:

- **Pull request** → `fmt`, `validate`, `plan`; the plan is posted (and updated) as a PR comment
- **Merge / push to `main`** → fresh plan, then `apply` waits for approval in the `production` environment
- **Daily 05:00 UTC** → drift check; Slack alert on drift or error
- Runs execute in Terraform Cloud; one at a time (concurrency group)
- Secrets: `TF_API_TOKEN` (Actions + Dependabot), `SLACK_WEBHOOK_URL`

Details, diagrams and secret renewal: [docs/terraform-workflow.md](docs/terraform-workflow.md).

## Pointing telegraf at InfluxDB Cloud

In `germanium-git/argocd`, `apps/telegraf/telegraf.conf`:

```toml
[[outputs.influxdb_v2]]
  urls = ["https://westeurope-1.azure.cloud2.influxdata.com"]
  token = "$INFLUXDB_TOKEN"
  organization = "15297d32235a99a0"   # org ID works as the organization
  bucket = "Network"
```

Then re-seal the token (the `telegraf` output above) as described in that app's `readme.md`.

## Free plan limits (check the current values in the InfluxDB docs)

- 2 buckets, 30-day retention
- writes 5 MB / 5 min, queries 300 MB / 5 min

Longer retention or a downsampled long-term bucket needs the Usage-Based plan.
Set `retention_days = 0` (infinite) after upgrading.

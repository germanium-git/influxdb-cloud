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

1. **InfluxDB Cloud UI** (`https://<region>.cloud2.influxdata.com`):
   - note the **region URL** (browser address bar) and the **organization name**
     (avatar → Organization → Settings)
   - create an **All Access API token** (Load Data → API Tokens → Generate) for Terraform
2. **Terraform Cloud**: `terraform login`, then `terraform init` creates the workspace
   `mygermanium/influxdb-cloud`. In the workspace → Variables add:
   - Environment variable `INFLUXDB_URL` = the region URL
   - Environment variable `INFLUXDB_TOKEN` = the All Access token, **sensitive**
   - Terraform variable `org_name` = the organization name
3. Plan and apply:
   ```sh
   terraform init
   terraform plan
   terraform apply
   ```
4. Read the generated tokens:
   ```sh
   terraform output -json writer_tokens | jq -r .telegraf
   terraform output -json writer_tokens | jq -r '."temp-monitor"'
   terraform output -raw reader_token
   ```

## Pointing telegraf at InfluxDB Cloud

In `germanium-git/argocd`, `apps/telegraf/telegraf.conf`:

```toml
[[outputs.influxdb_v2]]
  urls = ["https://<region>.cloud2.influxdata.com"]
  token = "$INFLUXDB_TOKEN"
  organization = "<org_name>"
  bucket = "Network"
```

Then re-seal the token (the `telegraf` output above) as described in that app's `readme.md`.

## Free plan limits (check the current values in the InfluxDB docs)

- 2 buckets, 30-day retention
- writes 5 MB / 5 min, queries 300 MB / 5 min

Longer retention or a downsampled long-term bucket needs the Usage-Based plan.
Set `retention_days = 0` (infinite) after upgrading.

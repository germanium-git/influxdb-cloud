locals {
  org_id = var.org_id
}

resource "influxdb_bucket" "this" {
  for_each = var.buckets

  org_id           = local.org_id
  name             = each.value.name
  description      = each.value.description
  retention_period = var.retention_days * 86400

  lifecycle {
    # Deleting a bucket deletes its data
    prevent_destroy = true
  }
}

# One write-only token per data source, scoped to its own bucket
resource "influxdb_authorization" "writer" {
  for_each = var.writers

  org_id      = local.org_id
  description = "${each.key}: write ${influxdb_bucket.this[each.value].name}"

  permissions = [{
    action = "write"
    resource = {
      type   = "buckets"
      id     = influxdb_bucket.this[each.value].id
      org_id = local.org_id
    }
  }]
}

# Read-only token for dashboards (e.g. Grafana), all managed buckets
resource "influxdb_authorization" "reader" {
  org_id      = local.org_id
  description = "dashboards: read ${join(", ", [for b in influxdb_bucket.this : b.name])}"

  permissions = [for b in influxdb_bucket.this : {
    action = "read"
    resource = {
      type   = "buckets"
      id     = b.id
      org_id = local.org_id
    }
  }]
}

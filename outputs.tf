output "org_id" {
  value = local.org_id
}

output "buckets" {
  description = "Bucket name => ID"
  value       = { for k, b in influxdb_bucket.this : b.name => b.id }
}

# Read with: terraform output -json writer_tokens | jq -r .telegraf
output "writer_tokens" {
  description = "Write tokens by writer name"
  value       = { for k, a in influxdb_authorization.writer : k => a.token }
  sensitive   = true
}

# Read with: terraform output -raw reader_token
output "reader_token" {
  description = "Read-only token for dashboards"
  value       = influxdb_authorization.reader.token
  sensitive   = true
}

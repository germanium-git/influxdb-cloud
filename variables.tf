variable "org_name" {
  description = "InfluxDB Cloud organization name (Organization -> Settings in the UI)"
  type        = string
}

variable "retention_days" {
  description = "Data retention for all buckets. The InfluxDB Cloud Free plan allows at most 30 days; 0 = infinite (Usage-Based plan only)."
  type        = number
  default     = 30

  validation {
    condition     = var.retention_days >= 0
    error_message = "retention_days must be 0 (infinite) or a positive number of days."
  }
}

variable "buckets" {
  description = "Buckets to create. The Free plan allows 2 buckets."
  type = map(object({
    name        = string
    description = string
  }))

  default = {
    network = {
      name        = "Network"
      description = "SNMP interface counters (SRX300, Dell switch) and LTE modem stats (RUT240) from telegraf in germanium-git/argocd apps/telegraf"
    }
    temperature = {
      name        = "Temperature"
      description = "temp-monitor temperature sensors"
    }
  }
}

variable "writers" {
  description = "Write-only tokens: token name => bucket key (from var.buckets)"
  type        = map(string)

  default = {
    telegraf     = "network"
    temp-monitor = "temperature"
  }
}

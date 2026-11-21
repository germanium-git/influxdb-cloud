terraform {
  required_version = ">= 1.5"

  required_providers {
    influxdb = {
      source  = "komminarlabs/influxdb"
      version = "~> 1.4"
    }
  }

  # State in Terraform Cloud, like the other germanium-git repos.
  # The workspace is created on the first `terraform init`.
  cloud {
    organization = "mygermanium"

    workspaces {
      name = "influxdb-cloud"
    }
  }
}

# The token comes from the environment variable INFLUXDB_TOKEN (sensitive
# environment variable in the Terraform Cloud workspace): an All Access API
# token from the InfluxDB Cloud UI.
provider "influxdb" {
  url = var.influxdb_url
}

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

# Credentials come from the environment (Terraform Cloud workspace
# environment variables, or your shell when running locally):
#   INFLUXDB_URL    e.g. https://eu-central-1-1.aws.cloud2.influxdata.com
#   INFLUXDB_TOKEN  an All Access API token from the InfluxDB Cloud UI
provider "influxdb" {}

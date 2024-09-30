###
### Cloud SQL - PostgreSQL
###
# Provider
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

# Variables
variable "project_id" {}
variable "region" {}
variable "name_prefix" {}
variable "database_version" {
  default = "POSTGRES_13"
}
variable "instance_type" {}
variable "network_id" {}
variable "instance_flags" {
  type    = list(map(string))
  default = []
}

# Environment Sufix
variable "environment" {
  default = ""
}
locals {
  delimiter = "${var.environment != "" ? "-" : ""}"
  env       = "${local.delimiter}${var.environment}"
}

# DB Instance
resource "random_id" "db_name_suffix" {
  byte_length = 4
}
resource "google_sql_database_instance" "postgresql" {
  name             = "${var.name_prefix}${local.env}-${random_id.db_name_suffix.hex}"
  database_version = var.database_version
  region           = var.region
  project          = var.project_id
  
  settings {
    tier              = var.instance_type
    availability_type = "ZONAL"
    disk_size         = 10
    
    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
      require_ssl     = true
    }
    
    backup_configuration {
      enabled    = true
      # Timezone GMT
      start_time = "04:00"
      
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 3
    }
    
    maintenance_window {
      # 7 = Sunday
      day          = 7
      
      # 06:00 UTC = 03:00 BRT
      hour         = 6
      update_track = "stable"
    }
    
    dynamic "database_flags" {
      for_each = var.instance_flags
      content {
        name  = database_flags.value.name
        value = database_flags.value.value
      }
    }
  }
  
  # @TODO = Alterar depois para 'true'
  deletion_protection = false
}

# Output
output "name" {
  value = google_sql_database_instance.postgresql.name
}
output "connection_name" {
  value = google_sql_database_instance.postgresql.connection_name
}
output "service_account_name" {
  value = google_sql_database_instance.postgresql.service_account_email_address
}
###
### SQL Import Data
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
variable "sql_instance_name" {}
variable "sql_service_account_name" {}
variable "storage_name" {}
variable "storage_location" {}
variable "import_files" {
  type = list(map(string))
}
variable "database_id" {}

# Environment Sufix
variable "environment" {
  default = ""
}
locals {
  delimiter = "${var.environment != "" ? "-" : ""}"
  env       = "${local.delimiter}${var.environment}"
}

/*
###
### SQL
###
data "google_sql_database_instance" "sql" {
  name    = var.instance_name
  project = var.project_id
}
*/

###
### Storage
###
# Create Cloud Storage
resource "random_id" "storage_name_suffix" {
  byte_length = 4
}
module "storage" {
  source = "../storage"
  
  project_id     = var.project_id
  name           = "${var.storage_name}-${random_id.storage_name_suffix.hex}"
  location       = var.storage_location
  uniform_access = true
  environment    = var.environment
}

# IAM Roles List
locals {
  iam_roles_list = [
    "roles/storage.legacyBucketReader", // Storage Legacy Bucket Reader
    "roles/storage.objectViewer",       // Storage Object Viewer
  ]
}

# Role Binding for Cloud SQL Service Account on Import Bucket
resource "google_storage_bucket_iam_member" "sql_read_storage" {
  count   = length(local.iam_roles_list)
  bucket  = module.storage.name
  role    = element(local.iam_roles_list, count.index)
  member  = "serviceAccount:${var.sql_service_account_name}"
}

# Upload files do Cloud Storage
resource "google_storage_bucket_object" "storage_file" {
  count  = length(var.import_files)
  name   = var.import_files[count.index].file_name
  bucket = module.storage.name
  source = var.import_files[count.index].local_path
  
  # Requires IAM binding permissions on the target Storage before upload
  depends_on = [google_storage_bucket_iam_member.sql_read_storage]
}

# Delay time to propragate all permissions on IAM
resource "time_sleep" "gsa_iam_permission_ready" {
  triggers = {
    sql_read_storage_ids = join(",", google_storage_bucket_iam_member.sql_read_storage.*.id)
  }
  
  depends_on = [google_storage_bucket_iam_member.sql_read_storage]
  create_duration = "60s"
}

# Run gcloud sql import command
locals {
  exec_gcloud_commands = [for s in var.import_files : "gcloud sql import sql ${var.sql_instance_name} gs://${module.storage.name}/${s.file_name} --database=${s.database} --user=${s.import_user} --project=${var.project_id} --quiet"]
}
resource "null_resource" "gcloud_sql_import" {
  triggers = {
    database_id = var.database_id
  }
  
  provisioner "local-exec" {
    command = join(" && \\\n", ["set -e"], local.exec_gcloud_commands)
  }
  
  # Requires SQL files on the target Storage before import
  depends_on = [
    time_sleep.gsa_iam_permission_ready,
    google_storage_bucket_object.storage_file,
    google_storage_bucket_iam_member.sql_read_storage
  ]
}
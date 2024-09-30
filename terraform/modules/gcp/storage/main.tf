###
### Storage
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
variable "name" {}
variable "location" {}
variable "uniform_access" {
  type = bool
}

# Environment Sufix
variable "environment" {
  default = ""
}
locals {
  delimiter = "${var.environment != "" ? "-" : ""}"
  env       = "${local.delimiter}${var.environment}"
}

# Storage
resource "google_storage_bucket" "storage" {
  name          = "${var.project_id}-${var.name}${local.env}"
  location      = var.location
  project       = var.project_id
  storage_class = "STANDARD"
  uniform_bucket_level_access = var.uniform_access
}

# Output
output "name" {
  value = google_storage_bucket.storage.name
}
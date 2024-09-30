###
### Service Account
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
variable "account_id" {}
variable "display_name" {}

# Environment Sufix
variable "environment" {
  default = ""
}
locals {
  delimiter = "${var.environment != "" ? "-" : ""}"
  env       = "${local.delimiter}${var.environment}"
}

# Service Account
resource "google_service_account" "sa" {
  account_id   = "${var.account_id}${local.env}"
  display_name = "${var.display_name}${local.env}"
  project      = var.project_id
}

# Output
output "name" {
  value = google_service_account.sa.name
}
output "email" {
  value = google_service_account.sa.email
}
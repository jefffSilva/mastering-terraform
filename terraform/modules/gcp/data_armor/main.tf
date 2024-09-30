###
### Cloud Armor
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

# Environment Sufix
variable "environment" {
  default = ""
}
locals {
  delimiter = "${var.environment != "" ? "-" : ""}"
  env       = "${local.delimiter}${var.environment}"
}

locals {
  google_compute_security_policy_name = "${var.name}${local.env}"
}

# Output
output "name" {
  value = local.google_compute_security_policy_name
}
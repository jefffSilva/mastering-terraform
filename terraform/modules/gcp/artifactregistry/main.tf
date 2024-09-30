###
### Artifact Registry
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
variable "location" {}

# Environment Sufix
variable "environment" {
  default = ""
}
locals {
  delimiter = "${var.environment != "" ? "-" : ""}"
  env       = "${local.delimiter}${var.environment}"
}

# @TODO = Criar repositorio / Copiar containers / Import/Export

/*
resource "google_artifact_registry_repository" "my-repo" {
  provider      = google-beta
  location      = var.location
  repository_id = "my-repository"
  description   = "example docker repository"
  format        = "DOCKER"
}
*/
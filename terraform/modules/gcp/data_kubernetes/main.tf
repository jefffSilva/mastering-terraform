###
### Kubernetes
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

# Environment Sufix
variable "environment" {
  default = ""
}
locals {
  delimiter = "${var.environment != "" ? "-" : ""}"
  env       = "${local.delimiter}${var.environment}"
}

# Node Pool Service Account
data "google_service_account" "gke_node_sa" {
  account_id = "${var.name}${local.env}-sa"
  project    = var.project_id
}

# GKE Cluster
data "google_container_cluster" "gke" {
  name     = "${var.name}${local.env}"
  location = var.location
  project  = var.project_id
}

# Output
output "name" {
  value = data.google_container_cluster.gke.name
}
output "location" {
  value = data.google_container_cluster.gke.location
}
output "endpoint" {
  value = data.google_container_cluster.gke.endpoint
}
output "cluster_ca_certificate" {
  value = data.google_container_cluster.gke.master_auth[0].cluster_ca_certificate
}
output "service_account_name" {
  value = data.google_service_account.gke_node_sa.email
}
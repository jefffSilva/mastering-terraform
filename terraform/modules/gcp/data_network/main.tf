###
### Network
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
variable "network_name" {}
variable "subnet_region" {}

# Environment Sufix
variable "environment" {
  default = ""
}
locals {
  delimiter = "${var.environment != "" ? "-" : ""}"
  env       = "${local.delimiter}${var.environment}"
}

# VPC
data "google_compute_network" "vpc" {
  name                    = "${var.network_name}${local.env}"
  project                 = var.project_id
}

# Subnet
data "google_compute_subnetwork" "subnet" {
  name          = "${var.subnet_region}-subnet"
  region        = var.subnet_region
  project       = var.project_id
}

# Output
output "network_name" {
  value = data.google_compute_network.vpc.name
}
output "network_id" {
  value = data.google_compute_network.vpc.id
}
output "subnet_name" {
  value = data.google_compute_subnetwork.subnet.name
}
output "subnet_id" {
  value = data.google_compute_subnetwork.subnet.id
}
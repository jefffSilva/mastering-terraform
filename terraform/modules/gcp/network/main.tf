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
variable "subnet_cidr_range" {}
variable "google_managed_range" {}
variable "google_managed_length" {
  type = number
}

variable "natgw_manual_ip_count" {
  type    = number
  default = 0
}
variable "natgw_min_ports_per_vm" {
  type    = number
  default = 64
}

# Environment Sufix
variable "environment" {
  default = ""
}
locals {
  delimiter = "${var.environment != "" ? "-" : ""}"
  env       = "${local.delimiter}${var.environment}"
}

# VPC
resource "google_compute_network" "vpc" {
  name                    = "${var.network_name}${local.env}"
  project                 = var.project_id
  auto_create_subnetworks = false
}

# Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.subnet_region}-subnet"
  region        = var.subnet_region
  ip_cidr_range = var.subnet_cidr_range
  network       = google_compute_network.vpc.id
  project       = google_compute_network.vpc.project
  private_ip_google_access = true
}

# Cloud Router
resource "google_compute_router" "router" {
  name    = "nat-router${local.env}"
  region  = google_compute_subnetwork.subnet.region
  network = google_compute_subnetwork.subnet.network
  project = google_compute_subnetwork.subnet.project
}

# Cloud NAT External IPs
resource "google_compute_address" "natgw_external_ips" {
  count   = var.natgw_manual_ip_count
  
  name    = "nat-gateway-ip-${count.index}${local.env}"
  region  = google_compute_subnetwork.subnet.region
  project = google_compute_subnetwork.subnet.project
}

# Cloud NAT
resource "google_compute_router_nat" "nat" {
  name    = "nat-gateway${local.env}"
  router  = google_compute_router.router.name
  region  = google_compute_router.router.region
  project = google_compute_router.router.project
  
  min_ports_per_vm       = var.natgw_min_ports_per_vm
  nat_ip_allocate_option = (var.natgw_manual_ip_count > 0) ? "MANUAL_ONLY" : "AUTO_ONLY"
  nat_ips                = google_compute_address.natgw_external_ips.*.self_link
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Address Range
resource "google_compute_global_address" "google_managed_services_range" {
  name          = "google-managed-services-range"
  address       = var.google_managed_range
  prefix_length = var.google_managed_length
  address_type  = "INTERNAL"
  purpose       = "VPC_PEERING"
  network       = google_compute_network.vpc.id
  project       = google_compute_network.vpc.project
}

# Private Service Access
resource "google_service_networking_connection" "private_service_access" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.google_managed_services_range.name]
}

########################
###  INGRESS RULES   ###
########################
# Allow SSH firewall rule from IAP
resource "google_compute_firewall" "allow_ssh_ingress_from_iap" {
  name    = "allow-ssh-ingress-from-iap${local.env}"
  network = google_compute_network.vpc.name
  
  source_ranges = ["35.235.240.0/20"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  project = var.project_id
}

# Allow HTTP firewall rule from Google Health Check
resource "google_compute_firewall" "allow_http_ingress_from_health_checks" {
  name    = "allow-http-ingress-from-health-checks${local.env}"
  network = google_compute_network.vpc.name
  
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  
  project = var.project_id
}

# Deny All Ingress firewall rule from Everything
resource "google_compute_firewall" "deny_all_ingress_from_everything" {
  name    = "deny-all-ingress-from-everything${local.env}"
  network = google_compute_network.vpc.name
  
  source_ranges = ["0.0.0.0/0"]
  direction     = "INGRESS"
  priority      = 65000
  
  deny {
    protocol = "all"
  }
  
  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
  
  project = var.project_id
}

########################
###   EGRESS RULES   ###
########################
# Allow HTTP(S) Egress firewall rule to Everything
resource "google_compute_firewall" "allow_http_egress_to_everything" {
  name    = "allow-http-egress-to-everything${local.env}"
  network = google_compute_network.vpc.name
  
  destination_ranges = ["0.0.0.0/0"]
  direction          = "EGRESS"
  
  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
  
  project = var.project_id
}

# Allow DNS Egress firewall rule to Everything
resource "google_compute_firewall" "allow_dns_egress_to_everything" {
  name    = "allow-dns-egress-to-everything${local.env}"
  network = google_compute_network.vpc.name
  
  destination_ranges = ["0.0.0.0/0"]
  direction          = "EGRESS"
  
  allow {
    protocol = "udp"
    ports    = ["53"]
  }
  
  project = var.project_id
}

# Allow Cloud SQL Proxy Auth Egress firewall rule to Google Managed Services
resource "google_compute_firewall" "allow_cloudsql_egress_to_google_managed_services" {
  name    = "allow-cloudsql-egress-to-google-managed-services${local.env}"
  network = google_compute_network.vpc.name
  
  destination_ranges = ["${var.google_managed_range}/${var.google_managed_length}"]
  direction          = "EGRESS"
  
  allow {
    protocol = "tcp"
    ports    = ["3307"]
  }
  
  project = var.project_id
}

# Deny All Egress firewall rule to Everything
resource "google_compute_firewall" "deny_all_egress_to_everything" {
  name    = "deny-all-egress-to-everything${local.env}"
  network = google_compute_network.vpc.name
  
  destination_ranges = ["0.0.0.0/0"]
  direction          = "EGRESS"
  priority           = 65000
  
  deny {
    protocol = "all"
  }
  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
  
  project = var.project_id
}

# Output
output "network_name" {
  value = google_compute_network.vpc.name
}
output "network_id" {
  value = google_compute_network.vpc.id
}
output "subnet_name" {
  value = google_compute_subnetwork.subnet.name
}
output "subnet_id" {
  value = google_compute_subnetwork.subnet.id
}
output "natgw_external_ips_address" {
  value = google_compute_address.natgw_external_ips.*.address
}
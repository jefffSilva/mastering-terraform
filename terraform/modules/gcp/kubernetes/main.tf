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
variable "network_id" {}
variable "subnet_id" {}
variable "subnet_cidr_range" {}
variable "name" {}
variable "location" {}
variable "subnet_pods" {}
variable "subnet_services" {}
variable "subnet_master" {}
variable "release_channel" {}
variable "master_version" {}
variable "min_node_count" {
  type = number
}
variable "max_node_count" {
  type = number
}
variable "machine_type" {}
variable "master_authorized_networks" {
  type = list(map(string))
}

# Environment Sufix
variable "environment" {
  default = ""
}
locals {
  delimiter = "${var.environment != "" ? "-" : ""}"
  env       = "${local.delimiter}${var.environment}"
}

# IAM Roles List
locals {
  iam_roles_list = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ]
}

# Node Pool Service Account
resource "google_service_account" "gke_node_sa" {
  account_id   = "${var.name}${local.env}-sa"
  display_name = "GKE Cluster Node Service Account"
  project      = var.project_id
}

# Role Binding for Node Pool Service Account
resource "google_project_iam_member" "gke_node_roles" {
  count   = length(local.iam_roles_list)
  project = var.project_id
  role    = element(local.iam_roles_list, count.index)
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

# GKE Cluster
resource "google_container_cluster" "gke" {
  name     = "${var.name}${local.env}"
  location = var.location
  
  enable_shielded_nodes    = true
  remove_default_node_pool = true
  initial_node_count       = 1
  
  network    = var.network_id
  subnetwork = var.subnet_id
  
  ip_allocation_policy {
    cluster_ipv4_cidr_block  = var.subnet_pods
    services_ipv4_cidr_block = var.subnet_services
  }
  
  min_master_version = var.master_version
  release_channel {
    channel = var.release_channel
  }
  
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.subnet_master
  }
  
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = lookup(cidr_blocks.value, "cidr_block", "")
        display_name = lookup(cidr_blocks.value, "display_name", "")
      }
    }
  }
  
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  
  maintenance_policy {
    daily_maintenance_window {
      # Timezone GMT
      start_time = "04:00"
    }
  }
  
  network_policy {
    provider = "CALICO"
    enabled  = true
  }
  
  addons_config {
    network_policy_config {
      disabled = false
    }
  }
  
  resource_labels = {
    isto_appliances = "gcp-gke"
    isto_containers = "gcp-gke"
  }
  
  project  = var.project_id

  # Requires IAM permission before creation
  depends_on = [google_project_iam_member.gke_node_roles]
}

# GKE Node Pool
resource "google_container_node_pool" "default" {
  name     = "default-pool"
  location = google_container_cluster.gke.location
  cluster  = google_container_cluster.gke.name
  initial_node_count = var.min_node_count
  
  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }
  
  management {
    auto_repair  = true
    auto_upgrade = true
  }
  
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
  
  node_config {
    disk_size_gb = 50
    disk_type    = "pd-standard"
    machine_type = var.machine_type
    tags         = ["gke-node", "gke-${google_container_cluster.gke.name}"]
    
    service_account = google_service_account.gke_node_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/sqlservice.admin"
    ]
  }
  
  # Requires IAM permission before creation
  depends_on = [google_project_iam_member.gke_node_roles]
}

# Allow Master Ingress firewall rule from Master to Nodes
resource "google_compute_firewall" "allow_master_ingress_to_gke_nodes" {
  name    = "allow-master-ingress-to-gke-nodes${local.env}"
  network = var.network_id
  
  target_tags   = ["gke-node"]
  source_ranges = ["${var.subnet_master}"]
  direction     = "INGRESS"
  
  allow {
    protocol = "all"
  }
  
  project = var.project_id
}

# Allow All Egress firewall rule to GKE Pods and Services
resource "google_compute_firewall" "allow_all_egress_to_gke_pods_services" {
  name    = "allow-all-egress-to-gke-pods-services${local.env}"
  network = var.network_id
  
  target_tags        = ["gke-node"]
  destination_ranges = ["${var.subnet_pods}", "${var.subnet_services}"]
  direction          = "EGRESS"
  
  allow {
    protocol = "all"
  }
  
  project = var.project_id
}

# Allow Kublet Metrics Egress firewall rule to GKE Nodes
resource "google_compute_firewall" "allow_metrics_egress_to_gke_pods" {
  name    = "allow-metrics-egress-to-gke-nodes${local.env}"
  network = var.network_id
  
  target_tags        = ["gke-node"]
  destination_ranges = ["${var.subnet_cidr_range}"]
  direction          = "EGRESS"
  
  allow {
    protocol = "tcp"
    ports    = ["10255"]
  }
  
  project = var.project_id
}

# Allow KubeProxy Egress firewall rule to Health Check Ingress IPs
resource "google_compute_firewall" "allow_kubeproxy_egress_to_health_check" {
  name    = "allow-kubeproxy-egress-to-health-check${local.env}"
  network = var.network_id
  
  target_tags        = ["gke-node"]
  destination_ranges = ["0.0.0.0/0"]
  direction          = "EGRESS"
  
  allow {
    protocol = "tcp"
    ports    = ["10256"]
  }
  
  project = var.project_id
}

# Output
output "name" {
  value = google_container_cluster.gke.name
}
output "location" {
  value = google_container_cluster.gke.location
}
output "endpoint" {
  value = google_container_cluster.gke.endpoint
}
output "cluster_ca_certificate" {
  value = google_container_cluster.gke.master_auth[0].cluster_ca_certificate
}
output "service_account_name" {
  value = google_service_account.gke_node_sa.email
}
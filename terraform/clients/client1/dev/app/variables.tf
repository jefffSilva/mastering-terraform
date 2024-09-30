# Variables
variable "project_id" {}
variable "region" {}
variable "terraform_service_account" {}
variable "environment_sufix" {}

# DNS
variable "dns_zone_name" {}

# GKE
variable "gke_cluster_name" {}
variable "gke_location" {}

# Cloud Armor
variable "armor_policy_name" {}

### client1s (App)
variable "app_ingress_ip_name_prefix" {}

variable "app_google_service_account" {}
variable "app_kubernetes_service_account" {}

variable "app_gke_namespace" {}

variable "app_storybook_hostname" {}
variable "app_portal_hostname" {}
variable "app_api_hostname" {}
variable "app_enable_storybook" {
  type = bool
  default = false
}

# Artifact Registry - App
variable "app_artifact_registry_name" {}
variable "app_artifact_registry_location" {}
variable "app_artifact_registry_project" {}
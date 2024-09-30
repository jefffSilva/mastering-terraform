# Variables
variable "project_id" {}
variable "region" {}
variable "terraform_service_account" {}
variable "environment_sufix" {}

# APIs
variable "apis_list" {
  type = list(string)
}

# Network
variable "network_name_prefix" {}
variable "subnet_cidr_range" {}
variable "google_managed_range" {}
variable "google_managed_length" {
  type = number
}
variable "natgw_manual_ip_count" {}

# SQL
variable "sql_instance_name_prefix" {}
variable "sql_database_version" {}
variable "sql_instance_type" {}
variable "sql_database" {}
variable "sql_username" {}
variable "sql_instance_flags" {
  type = list(map(string))
}

# GKE
variable "gke_cluster_name" {}
variable "gke_location" {}
variable "gke_subnet_pods" {}
variable "gke_subnet_services" {}
variable "gke_subnet_master" {}
variable "gke_release_channel" {}
variable "gke_master_version" {}
variable "gke_min_node_count" {
  type = number
}
variable "gke_max_node_count" {
  type = number
}
variable "gke_machine_type" {}
variable "gke_master_authorized_networks" {
  type = list(map(string))
}

# Storage
variable "storage_portal_name" {}
variable "storage_portal_location" {}

# Cloud Armor
variable "armor_policy_name" {}
variable "armor_policy_description" {}
variable "armor_default_action" {}
variable "armor_rules" {
  type = list(map(string))
}

# Memory store
variable "name_redis" {}
variable "tier_type" {}
variable "memory_size" {}
variable "region_id" {}
variable "connect_mode" {}
variable "redis_version" {}
variable "auth_enable" {}
variable "display_name" {}

# Secret manager 

variable "secret_id" {} 
variable "label" {}
variable "location_1" {}
variable "location_2" {}
variable "key" {}
variable "project_id" {}
variable "google_managed_range" {}
variable "google_managed_length" {}

variable "name_redis" {}
variable "tier_type" {}
variable "memory_size" {}
variable "region_id" {}
variable "connect_mode" {}
variable "redis_version" {}
variable "auth_enable" {}
variable "display_name" {}

variable "environment_sufix" {}

# Environment Sufix
variable "environment" {
  default = ""
}
locals {
  delimiter = "${var.environment != "" ? "-" : ""}"
  env       = "${local.delimiter}${var.environment}"
}

data "google_compute_network" "redis-network" {
  name = "client1-client-vpc-${var.environment_sufix}" 
}

resource "google_redis_instance" "cache" {
  name               = var.name_redis
  tier               = var.tier_type
  location_id        = var.region_id
  memory_size_gb     = var.memory_size
  authorized_network = data.google_compute_network.redis-network.id
  connect_mode       = var.connect_mode
  redis_version      = var.redis_version
  auth_enabled       = var.auth_enable
  display_name       = var.display_name

}

resource "google_compute_firewall" "allow-redis-egress-to-everything" {
  name    = "allow-redis-egress-to-everything"
  network = "client1-client-vpc-${var.environment_sufix}"
  
  destination_ranges = ["${var.google_managed_range}/${var.google_managed_length}"]
  direction          = "EGRESS"
  
  allow {
    protocol = "tcp"
    ports    = ["6379"]
  }
  
  project = var.project_id
  depends_on = [google_redis_instance.cache]
}

output "auth_string" {
  value = google_redis_instance.cache.auth_string
}
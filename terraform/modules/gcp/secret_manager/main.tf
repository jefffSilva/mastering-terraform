###
### Secret Manager
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
variable "key" {}
variable "value" {}
variable "secret_id" {} 
variable "label" {}
variable "location_1" {}
variable "location_2" {}

# creating a secret manager
resource "google_secret_manager_secret" "secret-basic" {
  secret_id = var.secret_id

  labels = {
    label = var.label
  }

  replication {
    user_managed {
      replicas {
        location = var.location_1
      }
      replicas {
        location = var.location_2
      }
    }
  }
}

# Creating a version from secret basic
resource "google_secret_manager_secret_version" "secret-version-basic" {
  secret = google_secret_manager_secret.secret-basic.id

  secret_data = <<EOF
  kind: Secret
  apiVersion: v1
  metadata:
    name: redis-gke-secret
    namespace: client1
  data:
    ${var.key}: ${base64encode(var.value)}
  EOF      
}
###
### APIs
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
variable "apis_list" {
  type = list(string)
}

# APIs
resource "google_project_service" "api" {
  count              = length(var.apis_list)
  project            = var.project_id
  service            = var.apis_list[count.index]
  disable_on_destroy = false
  disable_dependent_services = true
}
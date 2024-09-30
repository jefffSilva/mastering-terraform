# Providers
terraform {
  required_version = ">= 0.13"
  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

# Google Provider
# Note: Add 'Service Account Token Creator' to 'CloudBuild SA' on 'terraform SA'
provider "google" {
  project = var.project_id
  region  = var.region
  alias   = "impersonate"
  scopes  = [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/userinfo.email",
  ]
}

data "google_service_account_access_token" "terraform" {
  provider               = google.impersonate
  target_service_account = var.terraform_service_account
  scopes                 = ["userinfo-email", "cloud-platform"]
  lifetime               = "3600s"
}

provider "google" {
  project = var.project_id
  region  = var.region
  access_token = data.google_service_account_access_token.terraform.access_token
}
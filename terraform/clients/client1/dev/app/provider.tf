# Providers
terraform {
  required_version = ">= 0.13"
  required_providers {
    google = {
      source = "hashicorp/google"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
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

provider "google-beta" {
  project = var.project_id
  region  = var.region
  access_token = data.google_service_account_access_token.terraform.access_token
}

# Kubectl Provider
module "cluster" {
  source = "../../../../modules/gcp/data_kubernetes"
  
  project_id        = var.project_id
  name              = var.gke_cluster_name
  location          = var.gke_location
  environment       = var.environment_sufix
}

provider "kubectl" {
  host  = "https://${module.cluster.endpoint}"
  token = data.google_service_account_access_token.terraform.access_token
  cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
  load_config_file = false
}
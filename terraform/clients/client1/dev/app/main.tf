# GCP Backend
terraform {
  backend "gcs" {}
}

###
### GKE
###
module "gke" {
  source = "../../../../modules/gcp/data_kubernetes"
  
  project_id        = var.project_id
  name              = var.gke_cluster_name
  location          = var.gke_location
  environment       = var.environment_sufix
}

###
### Cloud Armor
###
module "armor" {
  source = "../../../../modules/gcp/data_armor"
  
  project_id     = var.project_id
  name           = var.armor_policy_name
  environment    = var.environment_sufix
}

###
### Application
###
# App client1s
module "app_client1s" {
  source = "../../../../modules/gcp/app_client1s"
  
  # General
  project_id                 = var.project_id
  region                     = var.region
  
  # DNS
  dns_zone_name              = var.dns_zone_name
  
  # Network
  ingress_ip_name_prefix     = var.app_ingress_ip_name_prefix
  
  # IAM
  google_service_account     = var.app_google_service_account
  kubernetes_service_account = var.app_kubernetes_service_account
  
  # GKE
  gke_namespace              = var.app_gke_namespace
  armor_policy_name          = module.armor.name
  
  # Application
  storybook_hostname         = var.app_storybook_hostname
  portal_hostname            = var.app_portal_hostname
  api_hostname               = var.app_api_hostname
  enable_storybook           = var.app_enable_storybook
  
  
  # GKE Artifact Registry
  artifact_registry_name     = var.app_artifact_registry_name
  artifact_registry_location = var.app_artifact_registry_location
  artifact_registry_project  = var.app_artifact_registry_project
  gke_service_account_name   = module.gke.service_account_name

  # Environment Sufix
  environment                = var.environment_sufix
}
# Variables
project_id                = "app-client1"
region                    = "us-east1"
terraform_service_account = ""
environment_sufix         = "dev"

# DNS
dns_zone_name             = "example.com"

# GKE
gke_cluster_name          = "client1-cluster"
gke_location              = "us-east1-b"

# Cloud Armor
armor_policy_name         = "client1-cloud-armor-policy"

### client1 (App)
# Network
app_ingress_ip_name_prefix     = "client1-ingress-ip"

# IAM
app_google_service_account     = "client1-api-sa"
app_kubernetes_service_account = "client1-api-sa"

# GKE
app_gke_namespace              = "client1"

# Application
app_storybook_hostname         = "app-client1.example.com"
app_portal_hostname            = "app-client1.example.com"
app_api_hostname               = "app-client1.example.com"
app_enable_storybook           = true

# Artifact Registry - App
app_artifact_registry_name     = "client1-docker"
app_artifact_registry_location = "us"
app_artifact_registry_project  = "shared1"
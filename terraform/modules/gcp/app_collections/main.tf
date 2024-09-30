###
### Artifact Registry
###
# Providers
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
    }
  }
}

# Variables
variable "project_id" {}
variable "region" {}

# DNS
variable "dns_zone_name" {}

# Network
variable "ingress_ip_name_prefix" {}

# IAM
variable "google_service_account" {}
variable "kubernetes_service_account" {}

# GKE
variable "gke_namespace" {}
variable "armor_policy_name" {}

# Application
variable "storybook_hostname" {}
variable "portal_hostname" {}
variable "api_hostname" {}
variable "callback_hostname" {}
variable "enable_storybook" {
  type = bool
}
variable "enable_callback" {
  type = bool
}
variable "enable_api" {
  type = bool
}

# GKE Artifact Registry
variable "artifact_registry_name" {}
variable "artifact_registry_location" {}
variable "artifact_registry_project" {}
variable "gke_service_account_name" {}

# Environment Sufix
variable "environment" {
  default = ""
}
locals {
  delimiter = "${var.environment != "" ? "-" : ""}"
  env       = "${local.delimiter}${var.environment}"
}

###
### GKE - IAM
###
# Adding IAM permission for Node SA to 'Artifact Registry Reader'
resource "google_artifact_registry_repository_iam_member" "artifact_registry_iam_member" {
  provider   = google-beta
  repository = var.artifact_registry_name
  location   = var.artifact_registry_location
  project    = var.artifact_registry_project
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${var.gke_service_account_name}"
}

###
### Network
###
# Global IP Reservation
resource "google_compute_global_address" "ingress_ip" {
  name         = "${var.ingress_ip_name_prefix}${local.env}"
  project      = var.project_id
}

###
### Cloud DNS
###
# Storybook DNS Record
resource "google_dns_record_set" "storybook" {
  count = (var.enable_storybook) ? 1 : 0
  managed_zone = var.dns_zone_name
  name         = "${var.storybook_hostname}."
  type         = "A"
  rrdatas      = ["${google_compute_global_address.ingress_ip.address}"]
  ttl          = 300
  project      = var.project_id
}

# Portal DNS Record
resource "google_dns_record_set" "portal" {
  managed_zone = var.dns_zone_name
  name         = "${var.portal_hostname}."
  type         = "A"
  rrdatas      = ["${google_compute_global_address.ingress_ip.address}"]
  ttl          = 300
  project      = var.project_id
}

# API DNS Record
resource "google_dns_record_set" "api" {
  count = (var.enable_api) ? 1 : 0
  managed_zone = var.dns_zone_name
  name         = "${var.api_hostname}."
  type         = "A"
  rrdatas      = ["${google_compute_global_address.ingress_ip.address}"]
  ttl          = 300
  project      = var.project_id
}

# Callback DNS Record
resource "google_dns_record_set" "callback" {
  count = (var.enable_callback) ? 1 : 0
  managed_zone = var.dns_zone_name
  name         = "${var.callback_hostname}."
  type         = "A"
  rrdatas      = ["${google_compute_global_address.ingress_ip.address}"]
  ttl          = 300
  project      = var.project_id
}

###
### Google Service Account
###
module "serviceaccount" {
  source = "../serviceaccount"
  
  project_id   = var.project_id
  account_id   = var.google_service_account
  display_name = var.google_service_account
  environment  = var.environment
}

###
### IAM
###
# Adding role permission in a project level (IAM)
resource "google_project_iam_member" "iam_role" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${module.serviceaccount.email}"
}

# Adding Workload Identity User permission in a service account level
resource "google_service_account_iam_member" "iam_member" {
  service_account_id = module.serviceaccount.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.gke_namespace}/${var.kubernetes_service_account}]"
}

###
### Kubectl
###
# Namespace
resource "kubectl_manifest" "namespace" {
  yaml_body = <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: ${var.gke_namespace}
YAML
}

# Kubernetes Service Account
resource "kubectl_manifest" "ksa" {
  yaml_body = <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  namespace: ${kubectl_manifest.namespace.name}
  name: ${var.kubernetes_service_account}
  annotations:
    iam.gke.io/gcp-service-account: ${module.serviceaccount.email}
YAML
}

# Kubernetes Service Account Role
resource "kubectl_manifest" "ksa_role" {
  yaml_body = <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: ${kubectl_manifest.namespace.name}
  name: ${kubectl_manifest.ksa.name}-role
rules:
  - apiGroups: ["", "extensions", "apps"]
    resources: ["configmaps", "pods", "services", "endpoints", "secrets"]
    verbs: ["get", "list", "watch"]
YAML
}

# Kubernetes Service Account RoleBinding
resource "kubectl_manifest" "ksa_rolebinding" {
  yaml_body = <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${kubectl_manifest.ksa.name}-rolebinding
  namespace: ${kubectl_manifest.namespace.name}
roleRef:
  kind: Role
  name: ${kubectl_manifest.ksa_role.name}
  apiGroup: ""
subjects:
  - kind: ServiceAccount
    name: ${kubectl_manifest.ksa.name}
    namespace: ${kubectl_manifest.namespace.name}
    apiGroup: ""
YAML
}

###
### Backend Config
###
# Graphql
data "kubectl_path_documents" "backendconfig_graphql" {
  pattern = "../../../../../kubernetes/collection/backendconfig/backendconfig.generic.yaml"
  vars = {
    namespace            = kubectl_manifest.namespace.name
    name                 = "graphql-backendconfig"
    health_check_path    = "/actuator/health"
    security_policy_name = var.armor_policy_name
  }
}
resource "kubectl_manifest" "backendconfig_graphql" {
  yaml_body = data.kubectl_path_documents.backendconfig_graphql.documents[0]
}

# Frontend
data "kubectl_path_documents" "backendconfig_frontend" {
  pattern = "../../../../../kubernetes/collection/backendconfig/backendconfig.generic.yaml"
  vars = {
    namespace            = kubectl_manifest.namespace.name
    name                 = "frontend-backendconfig"
    health_check_path    = "/"
    security_policy_name = var.armor_policy_name
  }
}
resource "kubectl_manifest" "backendconfig_frontend" {
  yaml_body = data.kubectl_path_documents.backendconfig_frontend.documents[0]
}

###
### Services
###
# Graphql
data "kubectl_path_documents" "service_graphql" {
  pattern = "../../../../../kubernetes/collection/service/service.generic.yaml"
  vars = {
    namespace     = kubectl_manifest.namespace.name
    name          = "graphql-svc"
    backendconfig = kubectl_manifest.backendconfig_graphql.name
    type          = "NodePort"
    app_name      = "graphql"
    target_port   = "8091"
  }
}
resource "kubectl_manifest" "service_graphql" {
  yaml_body = data.kubectl_path_documents.service_graphql.documents[0]
}

# Adapter
data "kubectl_path_documents" "service_adapter" {
  pattern = "../../../../../kubernetes/collection/service/service.generic.yaml"
  vars = {
    namespace     = kubectl_manifest.namespace.name
    name          = "adapter-svc"
    backendconfig = ""
    type          = "NodePort"
    app_name      = "adapter"
    target_port   = "8080"
  }
}
resource "kubectl_manifest" "service_adapter" {
  yaml_body = data.kubectl_path_documents.service_adapter.documents[0]
}

# Contestations API
data "kubectl_path_documents" "service_contestations_api" {
  pattern = "../../../../../kubernetes/collection/service/service.generic.yaml"
  vars = {
    namespace     = kubectl_manifest.namespace.name
    name          = "contestations-api-svc"
    backendconfig = ""
    type          = "NodePort"
    app_name      = "contestations-api"
    target_port   = "8080"
  }
}
resource "kubectl_manifest" "service_contestations_api" {
  yaml_body = data.kubectl_path_documents.service_contestations_api.documents[0]
}

# Customer API
data "kubectl_path_documents" "service_customer_api" {
  pattern = "../../../../../kubernetes/collection/service/service.generic.yaml"
  vars = {
    namespace     = kubectl_manifest.namespace.name
    name          = "customer-api-svc"
    backendconfig = ""
    type          = "NodePort"
    app_name      = "customer-api"
    target_port   = "8080"
  }
}
resource "kubectl_manifest" "service_customer_api" {
  yaml_body = data.kubectl_path_documents.service_customer_api.documents[0]
}

# Debts API
data "kubectl_path_documents" "service_debts_api" {
  pattern = "../../../../../kubernetes/collection/service/service.generic.yaml"
  vars = {
    namespace     = kubectl_manifest.namespace.name
    name          = "debts-api-svc"
    backendconfig = ""
    type          = "NodePort"
    app_name      = "debts-api"
    target_port   = "8080"
  }
}
resource "kubectl_manifest" "service_debts_api" {
  yaml_body = data.kubectl_path_documents.service_debts_api.documents[0]
}

# Domains API
data "kubectl_path_documents" "service_domains_api" {
  pattern = "../../../../../kubernetes/collection/service/service.generic.yaml"
  vars = {
    namespace     = kubectl_manifest.namespace.name
    name          = "domains-api-svc"
    backendconfig = ""
    type          = "NodePort"
    app_name      = "domains-api"
    target_port   = "8080"
  }
}
resource "kubectl_manifest" "service_domains_api" {
  yaml_body = data.kubectl_path_documents.service_domains_api.documents[0]
}

# Offers API
data "kubectl_path_documents" "service_offers_api" {
  pattern = "../../../../../kubernetes/collection/service/service.generic.yaml"
  vars = {
    namespace     = kubectl_manifest.namespace.name
    name          = "offers-api-svc"
    backendconfig = ""
    type          = "NodePort"
    app_name      = "offers-api"
    target_port   = "8080"
  }
}
resource "kubectl_manifest" "service_offers_api" {
  yaml_body = data.kubectl_path_documents.service_offers_api.documents[0]
}

# Companies API
data "kubectl_path_documents" "service_companies_api" {
  pattern = "../../../../../kubernetes/collection/service/service.generic.yaml"
  vars = {
    namespace     = kubectl_manifest.namespace.name
    name          = "companies-api-svc"
    backendconfig = ""
    type          = "NodePort"
    app_name      = "companies-api"
    target_port   = "8080"
  }
}
resource "kubectl_manifest" "service_companies_api" {
  yaml_body = data.kubectl_path_documents.service_companies_api.documents[0]
}

# Front WS
data "kubectl_path_documents" "service_front_ws" {
  pattern = "../../../../../kubernetes/collection/service/service.generic.yaml"
  vars = {
    namespace     = kubectl_manifest.namespace.name
    name          = "front-ws-svc"
    backendconfig = kubectl_manifest.backendconfig_frontend.name
    type          = "NodePort"
    app_name      = "front-ws"
    target_port   = "80"
  }
}
resource "kubectl_manifest" "service_front_ws" {
  yaml_body = data.kubectl_path_documents.service_front_ws.documents[0]
}

# Front Storybook
data "kubectl_path_documents" "service_front_storybook" {
  count = (var.enable_storybook) ? 1 : 0
  pattern = "../../../../../kubernetes/collection/service/service.generic.yaml"
  vars = {
    namespace     = kubectl_manifest.namespace.name
    name          = "front-storybook-svc"
    backendconfig = kubectl_manifest.backendconfig_frontend.name
    type          = "NodePort"
    app_name      = "front-storybook"
    target_port   = "80"
  }
}
resource "kubectl_manifest" "service_front_storybook" {
  count = (var.enable_storybook) ? 1 : 0
  yaml_body = data.kubectl_path_documents.service_front_storybook[0].documents[0]
}

# Front Callback
data "kubectl_path_documents" "service_callback" {
  pattern = "../../../../../kubernetes/collection/service/service.generic.yaml"
  vars = {
    namespace     = kubectl_manifest.namespace.name
    name          = "callback-svc"
    backendconfig = kubectl_manifest.backendconfig_frontend.name
    type          = "NodePort"
    app_name      = "callback"
    target_port   = "8080"
  }
}
resource "kubectl_manifest" "service_callback" {
  yaml_body = data.kubectl_path_documents.service_callback.documents[0]
}

###
### Managed Certificate
###
# API
data "kubectl_path_documents" "managedcertificate_api" {
  count = (var.enable_api) ? 1 : 0
  pattern = "../../../../../kubernetes/collection/managedcertificate/managedcertificate.generic.yaml"
  vars = {
    namespace = kubectl_manifest.namespace.name
    name      = "collection-api-cert"
    hostname  = var.api_hostname
  }
}
resource "kubectl_manifest" "managedcertificate_api" {
  count = (var.enable_api) ? 1 : 0
  yaml_body = data.kubectl_path_documents.managedcertificate_api[0].documents[0]
}

# Portal
data "kubectl_path_documents" "managedcertificate_portal" {
  pattern = "../../../../../kubernetes/collection/managedcertificate/managedcertificate.generic.yaml"
  vars = {
    namespace = kubectl_manifest.namespace.name
    name      = "collection-portal-cert"
    hostname  = var.portal_hostname
  }
}
resource "kubectl_manifest" "managedcertificate_portal" {
  yaml_body = data.kubectl_path_documents.managedcertificate_portal.documents[0]
}

# Storybook
data "kubectl_path_documents" "managedcertificate_storybook" {
  count = (var.enable_storybook) ? 1 : 0
  pattern = "../../../../../kubernetes/collection/managedcertificate/managedcertificate.generic.yaml"
  vars = {
    namespace = kubectl_manifest.namespace.name
    name      = "collection-storybook-cert"
    hostname  = var.storybook_hostname
  }
}
resource "kubectl_manifest" "managedcertificate_storybook" {
  count = (var.enable_storybook) ? 1 : 0
  yaml_body = data.kubectl_path_documents.managedcertificate_storybook[0].documents[0]
}

# Callback
data "kubectl_path_documents" "managedcertificate_callback" {
  count = (var.enable_callback) ? 1 : 0
  pattern = "../../../../../kubernetes/collection/managedcertificate/managedcertificate.generic.yaml"
  vars = {
    namespace = kubectl_manifest.namespace.name
    name      = "collection-callback-cert"
    hostname  = var.callback_hostname
  }
}
resource "kubectl_manifest" "managedcertificate_callback" {
  count = (var.enable_callback) ? 1 : 0
  yaml_body = data.kubectl_path_documents.managedcertificate_callback[0].documents[0]
}


###
### Frontend Config
###
data "kubectl_path_documents" "frontendconfig" {
  pattern = "../../../../../kubernetes/collection/frontendconfig/frontendconfig.generic.yaml"
  vars = {
    namespace = kubectl_manifest.namespace.name
    name      = "collection-frontendconfig"
  }
}
resource "kubectl_manifest" "frontendconfig" {
  yaml_body = data.kubectl_path_documents.frontendconfig.documents[0]
}

###
### Ingress
###
locals {
# managed_certificate_temp = "${kubectl_manifest.managedcertificate_api.name}, ${kubectl_manifest.managedcertificate_portal.name}"
  managed_certificate_temp = "${kubectl_manifest.managedcertificate_portal.name}"
  managed_certificate_name = (var.enable_storybook) ? "${local.managed_certificate_temp}, ${kubectl_manifest.managedcertificate_storybook[0].name}" : local.managed_certificate_temp
  managed_certificate_api  = (var.enable_api) ? "${local.managed_certificate_name}, ${kubectl_manifest.managedcertificate_api[0].name}" : local.managed_certificate_name
  managed_certificate_callback  = (var.enable_callback) ? "${local.managed_certificate_api}, ${kubectl_manifest.managedcertificate_callback[0].name}" : local.managed_certificate_api
}

data "kubectl_path_documents" "ingress_collection" {
  pattern = "../../../../../kubernetes/collection/ingress/collection-ingress.yaml"
  vars = {
    namespace                = kubectl_manifest.namespace.name
    global_static_ip_name    = google_compute_global_address.ingress_ip.name
    managed_certificate_name = local.managed_certificate_callback
    frontend_config_name     = kubectl_manifest.frontendconfig.name
    api_hostname             = var.api_hostname
    portal_hostname          = var.portal_hostname
    callback_hostname        = var.callback_hostname
    enable_storybook         = var.enable_storybook
    enable_callback          = var.enable_callback
    enable_api               = var.enable_api
    storybook_hostname       = var.storybook_hostname
  }
}
resource "kubectl_manifest" "ingress_collection" {
  yaml_body = data.kubectl_path_documents.ingress_collection.documents[0]
}
###
### WSO2 API Manager
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

# Database
variable "wso_sql_database" {}
variable "app_sql_database" {}
variable "wso_sql_data_schema" {
  type = map(map(string))
}
variable "app_sql_data_schema" {
  type = map(map(string))
}
variable "wso_sql_password" {}
variable "app_sql_password" {}
variable "sql_connection_name" {}

# IAM
variable "google_service_account" {}

# GKE
variable "gke_namespace" {}
variable "kubernetes_service_account" {}
variable "armor_policy_name" {}

# Nginx Controller
variable "nginx_ingress_ip_name" {}
variable "nginx_namespace" {}
variable "nginx_version" {}
variable "nginx_replicas" {}

# WSO2 Images
variable "container_images" {}

# WSO2 Erro Image
variable "error_image_registry" {}
variable "error_image_name" {}
variable "error_image_tag" {}

# WSO2
variable "api_hostname" {}
variable "api_manager_port" {
  type = number
}
variable "api_manager_ip_address" {}
variable "enable_ext_api_manager" {
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

#######################
###      WSO2       ###
#######################

# WSO2 Namespace
resource "kubectl_manifest" "wso2_namespace" {
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
  namespace: ${kubectl_manifest.wso2_namespace.name}
  name: ${var.kubernetes_service_account}
  annotations:
    iam.gke.io/gcp-service-account: ${module.serviceaccount.email}
YAML
}

# Delay time to propragate all permissions on IAM
resource "time_sleep" "ksa_iam_permission_ready" {
  triggers = {
    ksa_iam_permission_id = kubectl_manifest.ksa.id
  }
  
  depends_on = [kubectl_manifest.ksa, google_service_account_iam_member.iam_member]
  create_duration = "120s"
}

############################
###   WSO2 - ConfigMap   ###
############################
# ConfigMap - Environment Variables
data "kubectl_path_documents" "configmap_arch_envs" {
  pattern = "../../../../../kubernetes/wso2/configmap/arch-envs.yaml"
  vars = {
    namespace        = kubectl_manifest.wso2_namespace.name
    hostname         = (var.enable_ext_api_manager) ? var.api_manager_ip_address : "localhost"
    api_manager_port = var.api_manager_port
    jdbc_wso2_type   = "postgre"
    jdbc_wso2_driver = "org.postgresql.Driver"
    jdbc_wso2_url    = "jdbc:postgresql://localhost:5432/${var.wso_sql_database}?gssEncMode=disable"
    jdbc_apim_user   = var.wso_sql_data_schema["wsoapmdb"].username
    jdbc_is_user     = var.wso_sql_data_schema["wsoidb"].username
    jdbc_arti_user   = var.wso_sql_data_schema["wsoasdb"].username
    jdbc_shared_user = var.wso_sql_data_schema["wsoshadb"].username
    jdbc_perm_user   = var.wso_sql_data_schema["wsoampermdb"].username
    jdbc_stat_user   = var.wso_sql_data_schema["wsoamstatsdb"].username
    jdbc_dash_user   = var.wso_sql_data_schema["wsoamdashdb"].username
    jdbc_br_user     = var.wso_sql_data_schema["wsoambrdb"].username
    jdbc_wso2_pass   = var.wso_sql_password
  }
}
resource "kubectl_manifest" "configmap_arch_envs" {
  yaml_body = data.kubectl_path_documents.configmap_arch_envs.documents[0]
}

# ConfigMap - Configuration XMLs
data "kubectl_path_documents" "configmap_arch_wso2_xmls" {
  pattern = "../../../../../kubernetes/wso2/configmap/arch-wso2-xmls.yaml"
  vars = {
    namespace       = kubectl_manifest.wso2_namespace.name
    jdbc_app_url    = "jdbc:postgresql://localhost:5432/${var.app_sql_database}?gssEncMode=disable"
    jdbc_app_user   = var.app_sql_data_schema["app"].username
    jdbc_app_pass   = var.app_sql_password
    jdbc_app_driver = "org.postgresql.Driver"
  }
}
resource "kubectl_manifest" "configmap_arch_wso2_xmls" {
  yaml_body = data.kubectl_path_documents.configmap_arch_wso2_xmls.documents[0]
}

############################
###   WSO2 - Deployment  ###
############################
# StatefulSet - Identity Server
data "kubectl_path_documents" "statefulset_arch_wso2_identity_server" {
  pattern = "../../../../../kubernetes/wso2/statefulset/arch-wso2-identity-server.yaml"
  vars = {
    namespace       = kubectl_manifest.wso2_namespace.name
    container_image = var.container_images["identity_server"]
    configmap_envs  = kubectl_manifest.configmap_arch_envs.name
    configmap_xmls  = kubectl_manifest.configmap_arch_wso2_xmls.name
    instance_name   = var.sql_connection_name
    service_account = kubectl_manifest.ksa.name
  }
}
resource "kubectl_manifest" "statefulset_arch_wso2_identity_server" {
  yaml_body = data.kubectl_path_documents.statefulset_arch_wso2_identity_server.documents[0]
  
  # Requires IAM access before creation
  depends_on = [time_sleep.ksa_iam_permission_ready]
}

# Delay time to create and start Identity Server Container
resource "time_sleep" "identity_server_container_ready" {
  triggers = {
    identity_server_id = kubectl_manifest.statefulset_arch_wso2_identity_server.id
  }
  
  depends_on = [kubectl_manifest.statefulset_arch_wso2_identity_server]
  create_duration = "180s"
}

# StatefulSet - Traffic Manager
data "kubectl_path_documents" "statefulset_arch_wso2_traffic_manager" {
  pattern = "../../../../../kubernetes/wso2/statefulset/arch-wso2-traffic-manager.yaml"
  vars = {
    namespace       = kubectl_manifest.wso2_namespace.name
    container_image = var.container_images["traffic_manager"]
    configmap_envs  = kubectl_manifest.configmap_arch_envs.name
    configmap_xmls  = kubectl_manifest.configmap_arch_wso2_xmls.name
    instance_name   = var.sql_connection_name
    service_account = kubectl_manifest.ksa.name
  }
}
resource "kubectl_manifest" "statefulset_arch_wso2_traffic_manager" {
  yaml_body = data.kubectl_path_documents.statefulset_arch_wso2_traffic_manager.documents[0]
  
  # Requires IAM access before creation
  depends_on = [
    kubectl_manifest.statefulset_arch_wso2_identity_server,
    time_sleep.identity_server_container_ready
  ]
}

# Deployment - API Manager
data "kubectl_path_documents" "deployment_arch_wso2_api_manager" {
  pattern = "../../../../../kubernetes/wso2/deployment/arch-wso2-api-manager.yaml"
  vars = {
    namespace       = kubectl_manifest.wso2_namespace.name
    container_image = var.container_images["api_manager"]
    configmap_envs  = kubectl_manifest.configmap_arch_envs.name
    configmap_xmls  = kubectl_manifest.configmap_arch_wso2_xmls.name
    instance_name   = var.sql_connection_name
    service_account = kubectl_manifest.ksa.name
  }
}
resource "kubectl_manifest" "deployment_arch_wso2_api_manager" {
  yaml_body = data.kubectl_path_documents.deployment_arch_wso2_api_manager.documents[0]
  
  # Requires IAM access before creation
  depends_on = [
    kubectl_manifest.statefulset_arch_wso2_identity_server,
    time_sleep.identity_server_container_ready
  ]
}

# Deployment - Gateway
data "kubectl_path_documents" "deployment_arch_wso2_gateway" {
  pattern = "../../../../../kubernetes/wso2/deployment/arch-wso2-gateway.yaml"
  vars = {
    namespace       = kubectl_manifest.wso2_namespace.name
    container_image = var.container_images["api_gateway"]
    configmap_envs  = kubectl_manifest.configmap_arch_envs.name
    configmap_xmls  = kubectl_manifest.configmap_arch_wso2_xmls.name
    instance_name   = var.sql_connection_name
    service_account = kubectl_manifest.ksa.name
  }
}
resource "kubectl_manifest" "deployment_arch_wso2_gateway" {
  yaml_body = data.kubectl_path_documents.deployment_arch_wso2_gateway.documents[0]
  
  # Requires IAM access before creation
  depends_on = [
    kubectl_manifest.statefulset_arch_wso2_identity_server,
    time_sleep.identity_server_container_ready
  ]
}

############################
###    WSO2 - Services   ###
############################
# Service - Publisher (External)
data "kubectl_path_documents" "service_arch_publisher_service" {
  count = (var.enable_ext_api_manager) ? 1 : 0
  pattern = "../../../../../kubernetes/wso2/service/arch-publisher-service.yaml"
  vars = {
    namespace        = kubectl_manifest.wso2_namespace.name
    loadbalancer_ip  = var.api_manager_ip_address
    api_manager_port = var.api_manager_port
  }
}
resource "kubectl_manifest" "service_arch_publisher_service" {
  count = (var.enable_ext_api_manager) ? 1 : 0
  yaml_body = data.kubectl_path_documents.service_arch_publisher_service[0].documents[0]
}

# Service - API Manager
data "kubectl_path_documents" "service_arch_api_manager_service" {
  pattern = "../../../../../kubernetes/wso2/service/arch-api-manager-service.yaml"
  vars = {
    namespace        = kubectl_manifest.wso2_namespace.name
    api_manager_port = var.api_manager_port
  }
}
resource "kubectl_manifest" "service_arch_api_manager_service" {
  yaml_body = data.kubectl_path_documents.service_arch_api_manager_service.documents[0]
}

# Service - Traffic Manager
data "kubectl_path_documents" "service_arch_traffic_manager_service" {
  pattern = "../../../../../kubernetes/wso2/service/arch-traffic-manager-service.yaml"
  vars = {
    namespace = kubectl_manifest.wso2_namespace.name
  }
}
resource "kubectl_manifest" "service_arch_traffic_manager_service" {
  yaml_body = data.kubectl_path_documents.service_arch_traffic_manager_service.documents[0]
}

# Service - Identity Server
data "kubectl_path_documents" "service_arch_identity_server_service" {
  pattern = "../../../../../kubernetes/wso2/service/arch-identity-server-service.yaml"
  vars = {
    namespace = kubectl_manifest.wso2_namespace.name
  }
}
resource "kubectl_manifest" "service_arch_identity_server_service" {
  yaml_body = data.kubectl_path_documents.service_arch_identity_server_service.documents[0]
}

# Service - Gateway
data "kubectl_path_documents" "service_arch_api_gateway_service" {
  pattern = "../../../../../kubernetes/wso2/service/arch-api-gateway-service.yaml"
  vars = {
    namespace = kubectl_manifest.wso2_namespace.name
  }
}
resource "kubectl_manifest" "service_arch_api_gateway_service" {
  yaml_body = data.kubectl_path_documents.service_arch_api_gateway_service.documents[0]
}

############################
###     NGINX Ingress    ###
############################
###
### Kubectl
###
# Nginx Namespace
resource "kubectl_manifest" "nginx_namespace" {
  yaml_body = <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: ${var.nginx_namespace}
YAML
}

# Backend Config
data "kubectl_path_documents" "backendconfig_ingress_nginx" {
  pattern = "../../../../../kubernetes/nginx/backendconfig/ingress-nginx-backendconfig.yaml"
  vars = {
    namespace         = kubectl_manifest.nginx_namespace.name
    armor_policy_name = var.armor_policy_name
  }
}
resource "kubectl_manifest" "backendconfig_ingress_nginx" {
  yaml_body = data.kubectl_path_documents.backendconfig_ingress_nginx.documents[0]
}

###
### Helm
###
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.nginx_version
  namespace        = kubectl_manifest.nginx_namespace.name
  create_namespace = false
  timeout          = 600
  
  set {
    name = "controller.replicaCount"
    value = var.nginx_replicas
  }
  set {
    name = "controller.service.type"
    value = "NodePort"
  }
  set {
    name = "controller.service.enableHttps"
    value = "false"
  }
  set {
    name = "controller.service.annotations.cloud\\.google\\.com/backend-config"
    value = "\\{\"default\": \"${kubectl_manifest.backendconfig_ingress_nginx.name}\"\\}"
  }
  set {
    name = "defaultBackend.enabled"
    value = "true"
  }
  set {
    name = "defaultBackend.image.registry"
    value = var.error_image_registry
  }
  set {
    name = "defaultBackend.image.image"
    value = var.error_image_name
  }
  set {
    name = "defaultBackend.image.tag"
    value = var.error_image_tag
  }
}

# Managed Certificate
data "kubectl_path_documents" "managedcertificate_ingress_nginx" {
  pattern = "../../../../../kubernetes/nginx/managedcertificate/ingress-nginx-cert.yaml"
  vars = {
    namespace    = kubectl_manifest.nginx_namespace.name
    api_hostname = var.api_hostname
  }
}
resource "kubectl_manifest" "managedcertificate_ingress_nginx" {
  yaml_body = data.kubectl_path_documents.managedcertificate_ingress_nginx.documents[0]
}

# Frontend Config
data "kubectl_path_documents" "frontendconfig_ingress_nginx" {
  pattern = "../../../../../kubernetes/nginx/frontendconfig/ingress-nginx-frontendconfig.yaml"
  vars = {
    namespace = kubectl_manifest.nginx_namespace.name
  }
}
resource "kubectl_manifest" "frontendconfig_ingress_nginx" {
  yaml_body = data.kubectl_path_documents.frontendconfig_ingress_nginx.documents[0]
}

# Ingress
data "kubectl_path_documents" "ingress_nginx_ingress_gce" {
  pattern = "../../../../../kubernetes/nginx/ingress/ingress-nginx-gce.yaml"
  vars = {
    namespace                = kubectl_manifest.nginx_namespace.name
    global_static_ip_name    = var.nginx_ingress_ip_name
    managed_certificate_name = kubectl_manifest.managedcertificate_ingress_nginx.name
    frontend_config_name     = kubectl_manifest.frontendconfig_ingress_nginx.name
  }
}
resource "kubectl_manifest" "ingress_nginx_ingress_gce" {
  yaml_body = data.kubectl_path_documents.ingress_nginx_ingress_gce.documents[0]
  
  # Requires that the nginx service exists before creation
  depends_on = [helm_release.ingress_nginx]
}

############################
###    WSO2 - Ingress    ###
############################
# Ingress - API Gateway
data "kubectl_path_documents" "ingress_api_gateway" {
  pattern = "../../../../../kubernetes/wso2/ingress/ingress-api-gateway.yaml"
  vars = {
    namespace    = kubectl_manifest.wso2_namespace.name
    api_hostname = var.api_hostname
  }
}
resource "kubectl_manifest" "ingress_api_gateway" {
  yaml_body = data.kubectl_path_documents.ingress_api_gateway.documents[0]
  
  # Requires services exists before creation
  depends_on = [
    helm_release.ingress_nginx,
    kubectl_manifest.service_arch_api_gateway_service
  ]
}

# Ingress - Totp
data "kubectl_path_documents" "ingress_totp" {
  pattern = "../../../../../kubernetes/wso2/ingress/ingress-totp.yaml"
  vars = {
    namespace    = kubectl_manifest.wso2_namespace.name
    api_hostname = var.api_hostname
  }
}
resource "kubectl_manifest" "ingress_totp" {
  yaml_body = data.kubectl_path_documents.ingress_totp.documents[0]
  
  # Requires services exists before creation
  depends_on = [
    helm_release.ingress_nginx,
    time_sleep.identity_server_container_ready
  ]
}

# Ingress - Carbon
data "kubectl_path_documents" "ingress_carbon" {
  pattern = "../../../../../kubernetes/wso2/ingress/ingress-carbon.yaml"
  vars = {
    namespace    = kubectl_manifest.wso2_namespace.name
    api_hostname = var.api_hostname
  }
}
resource "kubectl_manifest" "ingress_carbon" {
  yaml_body = data.kubectl_path_documents.ingress_carbon.documents[0]
  
  # Requires services exists before creation
  depends_on = [
    helm_release.ingress_nginx,
    time_sleep.identity_server_container_ready
  ]
}
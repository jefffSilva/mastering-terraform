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

# Network 
variable "network_name" {}
# IAM
variable "google_service_account" {}
variable "kubernetes_service_account" {}

# GKE
variable "gke_namespace" {}

# GKE Artifact Registry
variable "artifact_registry_name" {}
variable "artifact_registry_location" {}
variable "artifact_registry_project" {}
variable "gke_service_account_name" {}

# Database
variable "sql_instance_name_prefix" {}
variable "sql_database_version" {}
variable "sql_instance_type" {}
variable "sql_instance_flags" {
  type = list(map(string))
}


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

###
### SQL
###
module "pgsql" {
  source = "../sql"
  
  project_id       = var.project_id
  region           = var.region
  name_prefix      = var.sql_instance_name_prefix
  database_version = var.sql_database_version
  instance_type    = var.sql_instance_type
  instance_flags   = var.sql_instance_flags
  network_id       = "projects/${var.project_id}/global/networks/${var.network_name}-${var.environment}"
  environment      = var.environment
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
### Configmap
###

# esign-config-map
data "kubectl_path_documents" "esign-config-map" {
  pattern = "../../../../../kubernetes/docmosis/configmap/esign-config-map.yml"
  vars = {
    namespace                         = kubectl_manifest.namespace.name
    name                              = "arch-envs-esign"
    ucp_esign_url                     = "jdbc:postgresql://127.0.0.1:5432/wlfidesenv?gssEncMode=disable&currentSchema=wlfidesenv"
    ucp_esign_user                    = "docmosis"
    ucp_esign_pass                    = "hdhdffim46aoxljh"
    ucp_esign_driver                  = "org.postgresql.Driver"
    ucp_esign_dialect                 = "org.hibernate.dialect.PostgreSQLDialect"
    ucp_esign_maxpoolsize             = "20"
    log_esign_spring                  = "INFO"
    log_esign_log4j                   = "classpath:log4j2.xml"
    log_esign_hibernate_sql           = "INFO"
    log_esign_level_root              = "INFO"
    log_esign_jpa_sql                 = "false"
    esign_port                        = "8090"
    esign_url_base                    = "x"
    esign_cert_url                    = "/opt/esign/data/sender_keystore.p12"
    esign_cert_type                   = "PKCS12"
    esign_ecm_url_base                = "http://documents-api-svc"
    esign_ecm_url_upload              = "/ecm/uploadrest"
    esign_ecm_url_uploadversion       = "/ecm/documentupload"
    esign_ecm_url_download            = "/ecm/donwloadrest/"
    esign_ecm_url_downloadversion     = "/ecm/downloadbyversionrest/"
    esign_url                         = "http://arch-esign-app-service:8090"
    esign_wso2_url_token              = "8247"
    esign_wso2_imob_hostname          = "http://arch-api-gateway-service.wso2.svc.cluster.local/"
    esign_token_authorization         = "basic yzniqk9qmxdxnknisfg3uuhsy1vymmjmzhc4ytpovuq0rfd4dmpldk1tcfjnsvvmt2ixuwzvm2nh"
    esign_redis_ttl_ms                = "900000"
    esign_redis_baseurl               = "redis://10.162.64.4:6379"
    email_baseurl                     = "x"
    azure_client_id                   = "x"
    azure_client_secret               = "x"
    azure_certificate_name            = "x"
    azure_certificate_hash            = "x"
    azure_certificate_chain_enable    = "false"
    azure_certificate_parent_hash     = "x"
    azure_certificate_root_hash       = "x"
    azure_key_version                 = "x"
    azure_tenant_id                   = "x"
    azure_key_vault_url               = "x"
    server_undertow_io_threads        = "16"
    server_undertow_worker_threads    = "40"
    kafka_enabled                     = "false"
    kafka_host                        = "x"
    kafka_producer_enabled            = "x"
    kafka_consumer_enabled            = "x"
    kafka_group_id                    = "x"
    esign_cert_external               = "false"
    elastic_apm_enabled               = "false"
    wso2_gw_hostname                  = "arch-api-gateway-service.wso2.svc.cluster.local"
  }
}
resource "kubectl_manifest" "esign-config-map" {
  yaml_body = data.kubectl_path_documents.esign-config-map.documents[0]
}


# docmosis-config-map
data "kubectl_path_documents" "docmosis-config-map" {
  pattern = "../../../../../kubernetes/docmosis/configmap/arch-brc6auto-prd.yml"
  vars = {
    namespace                           = kubectl_manifest.namespace.name
    name                                = "docmosis-config-map"
    ucp_ccs_url                         = "jdbc:postgresql://127.0.0.1:5432/wlfidesenv?gssEncMode=disable"
    ucp_ccs_user                        = "docmosis"
    ucp_ccs_pass                        = "hdhDFfiM46aOxLJH"
    ucp_ccs_dialect                     = "org.hibernate.dialect.PostgreSQLDialect"
    ucp_ccs_driver                      = "org.postgresql.Driver"
    ucp_ccs_maxpoolsize                 = "20"
    ucp_ccs_conwaittimeout              = "250"
    arch_ccstornado_baseurl             = "http://arch-ccs-tornado-service:8080"
    arch_ecm_baseurl                    = "http://arch-ccs-gateway-service:8090"
    log_log4j                           = "classpath:log4j2.xml"
    log_ccs_hibernate_sql               = "INFO"
    log_ccs_jpa_sql                     = "true"
    log_ccs_spring                      = "INFO"
    log_ccs_level_root                  = "DEBUG"
    server_undertow_ccs_io_threads      = "16"
    server_undertow_ccs_worker_threads  = "40"
    docmosis_key                        = "4NAD-KLTN-JALP-DLIA-JAIE-3KLH-PKFQ-GR58-2C5E-3-2236"
    docmosis_site                       = "Licensed To: Vivere Brasil Servicos e Solucoes S.A. For OEM use with project: Vivere. Up to 6 deployments"
  }
}
resource "kubectl_manifest" "docmosis-config-map" {
  yaml_body = data.kubectl_path_documents.docmosis-config-map.documents[0]
}


###
### volume pvc
###
# pvc-ccs-tornado
data "kubectl_path_documents" "pvc-ccs-tornado" {
  pattern = "../../../../../kubernetes/docmosis/volumes/pvc-ccs-tornado.yml"
  vars = {
    namespace            = kubectl_manifest.namespace.name
    name                 = "pvc-ccs-tornado"
    storage              = "30Gi"
  }
}
resource "kubectl_manifest" "pvc-ccs-tornado" {
  yaml_body = data.kubectl_path_documents.pvc-ccs-tornado.documents[0]
}

###
### Deployment
###
# ccs-gateway
data "kubectl_path_documents" "ccs-gateway" {
  pattern = "../../../../../kubernetes/docmosis/deployments/ccs-gateway.yml"
  vars = {
    namespace            = kubectl_manifest.namespace.name
    name                 = "arch-ccs-gateway"
    instance             = module.pgsql.connection_name
  }
}
resource "kubectl_manifest" "ccs-gateway" {
  yaml_body = data.kubectl_path_documents.ccs-gateway.documents[0]
}

###
### Deployment
###
# ccs-tornado
data "kubectl_path_documents" "ccs-tornado" {
  pattern = "../../../../../kubernetes/docmosis/deployments/ccs-tornado.yml"
  vars = {
    namespace            = kubectl_manifest.namespace.name
    name                 = "arch-ccs-tornado"
    instance             = module.pgsql.connection_name
  }
}
resource "kubectl_manifest" "ccs-tornado" {
  yaml_body = data.kubectl_path_documents.ccs-tornado.documents[0]
}

# esign-backend-app
data "kubectl_path_documents" "esign-backend-app" {
  pattern = "../../../../../kubernetes/docmosis/deployments/microservice-esign-backend-app.yml"
  vars = {
    namespace            = kubectl_manifest.namespace.name
    name                 = "arch-esign-app"
    instance             = module.pgsql.connection_name
  }
}
resource "kubectl_manifest" "esign-backend-app" {
  yaml_body = data.kubectl_path_documents.esign-backend-app.documents[0]
}

# esign-backend-graphql
data "kubectl_path_documents" "esign-backend-graphql" {
  pattern = "../../../../../kubernetes/docmosis/deployments/esign-backend-graphql.yml"
  vars = {
    namespace            = kubectl_manifest.namespace.name
    name                 = "arch-graphql-esign-app"
  }
}
resource "kubectl_manifest" "esign-backend-graphql" {
  yaml_body = data.kubectl_path_documents.esign-backend-graphql.documents[0]
}

###
### Service
###
# arch-ccs-gateway-service
data "kubectl_path_documents" "service_ccs-gateway" {
  pattern = "../../../../../kubernetes/client1/service/service.generic.yaml"
  vars = {
    namespace     = kubectl_manifest.namespace.name
    name          = "arch-ccs-gateway-svc"
    backendconfig = ""
    type          = "NodePort"
    app_name      = "arch-ccs-gateway"
    target_port   = "8090"
  }
}
resource "kubectl_manifest" "service_ccs-gateway" {
  yaml_body = data.kubectl_path_documents.service_ccs-gateway.documents[0]
}

# arch-ccs-tornado
data "kubectl_path_documents" "ccs-tornado-service" {
  pattern = "../../../../../kubernetes/client1/service/service.generic.yaml"
  vars = {
    namespace     = kubectl_manifest.namespace.name
    name          = "arch-ccs-tornado-svc"
    backendconfig = ""
    type          = "ClusterIP"
    app_name      = "arch-ccs-tornado"
    target_port   = "8080"
  }
}
resource "kubectl_manifest" "ccs-tornado-service" {
  yaml_body = data.kubectl_path_documents.ccs-tornado-service.documents[0]
}

# arch-esign-app-service
data "kubectl_path_documents" "esign-app-service" {
  pattern = "../../../../../kubernetes/client1/service/service.generic.yaml"
  vars = {
    namespace     = kubectl_manifest.namespace.name
    name          = "arch-esign-app-svc"
    backendconfig = ""
    type          = "ClusterIP"
    app_name      = "arch-esign-app"
    target_port   = "8090"
  }
}
resource "kubectl_manifest" "esign-app-service" {
  yaml_body = data.kubectl_path_documents.esign-app-service.documents[0]
}

# arch-graphql-esign-app-service
data "kubectl_path_documents" "graphql-esign-app-service" {
  pattern = "../../../../../kubernetes/client1/service/service.generic.yaml"
  vars = {
    namespace     = kubectl_manifest.namespace.name
    name          = "arch-graphql-esign-app-svc"
    backendconfig = ""
    type          = "ClusterIP"
    app_name      = "arch-graphql-esign-app"
    target_port   = "8090"
  }
}
resource "kubectl_manifest" "graphql-esign-app-service" {
  yaml_body = data.kubectl_path_documents.graphql-esign-app-service.documents[0]
}
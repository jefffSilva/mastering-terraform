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
variable "gke_cluster_name" {}
variable "gke_clientid" {}
variable "gke_secret" {}
variable "environment_sufix" {}

variable "client_resume" {}

variable "app_gke_namespace" {}

# Secrets
resource "kubectl_manifest" "secret-k8s" {
  yaml_body = <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: ${var.gke_cluster_name}-${var.environment_sufix}-${var.client_resume}
  namespace: ${var.app_gke_namespace}
type: bootstrap.kubernetes.io/token
data:
  clientId: ${var.gke_clientid}
  secret: ${var.gke_secret}
YAML
}

  

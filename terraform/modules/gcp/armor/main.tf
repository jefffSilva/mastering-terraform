###
### Cloud Armor
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
variable "name" {}
variable "description" {}
variable "default_action" {}
variable "rules" {
  type = list(map(string))
}
variable "natgw_external_ips" {
  type    = list(string)
  default = []
}

# Environment Sufix
variable "environment" {
  default = ""
}
locals {
  delimiter = "${var.environment != "" ? "-" : ""}"
  env       = "${local.delimiter}${var.environment}"
}

# Cloud Armor Security Policy
locals {
  natgw_ips = join(",", [for v in var.natgw_external_ips : "${v}/32"])
  natgw_rule = (local.natgw_ips != "") ? [for v in [local.natgw_ips] : {
      action        = "allow"
      priority      = 1100
      description   = "NAT Gateway"
      src_ip_ranges = v
    }
  ] : []
  rules = concat(var.rules, local.natgw_rule)
}
resource "google_compute_security_policy" "policy" {
  name        = "${var.name}${local.env}"
  description = var.description
  project     = var.project_id
  
  # Default rule
  rule {
    action      = var.default_action
    priority    = "2147483647"
    description = "Default rule"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
  
  # More rules
  dynamic "rule" {
    for_each = local.rules
    content {
      action      = lookup(rule.value, "action", "deny(403)")
      priority    = lookup(rule.value, "priority", ((rule.key + 1) * 100))
      description = lookup(rule.value, "description", "")
      match {
        versioned_expr = contains(keys(rule.value), "src_ip_ranges") ? "SRC_IPS_V1" : null
        dynamic "config" {
          for_each = contains(keys(rule.value), "src_ip_ranges") ? [rule.value.src_ip_ranges] : []
          content {
            src_ip_ranges = split(",", config.value)
          }
        }
        dynamic "expr" {
          for_each = contains(keys(rule.value), "expression") ? [rule.value.expression] : []
          content {
            expression = expr.value
          }
        }
      }
    }
  }
}

# Output
output "name" {
  value = google_compute_security_policy.policy.name
}
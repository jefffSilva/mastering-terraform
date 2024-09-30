###
### WSO2 API Manager - Infra
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
variable "nginx_ingress_ip_name_prefix" {}

# Database
variable "sql_instance_name_prefix" {}
variable "sql_database_version" {}
variable "sql_instance_type" {}
variable "sql_instance_flags" {
  type = list(map(string))
}
variable "wso_sql_database" {}
variable "app_sql_database" {}
variable "wso_sql_data_schema" {
  type = map(map(string))
}
variable "app_sql_data_schema" {
  type = map(map(string))
}

# Storage
variable "storage_sql_name" {}
variable "storage_sql_location" {}

# GKE
variable "gke_namespace" {}
variable "kubernetes_service_account" {}

# WSO2
variable "api_hostname" {}
variable "api_manager_ip_name_prefix" {}
variable "enable_ext_api_manager" {
  type = bool
}

# Environment Sufix
variable "environment" {
  default = ""
}
locals {
  delimiter = "${var.environment != "" ? "-" : ""}"
  env       = "${local.delimiter}${var.environment}"
}

# API Manager External Service IP Reservation
resource "google_compute_address" "api_manager_ip" {
  count   = (var.enable_ext_api_manager) ? 1 : 0
  name    = "${var.api_manager_ip_name_prefix}${local.env}"
  region  = var.region
  project = var.project_id
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
  network_id       = "projects/${var.project_id}/global/networks/${var.network_name}"
  environment      = var.environment
}

###
### SQL User
###
# WSO2 Username/Password
resource "random_password" "wso_sql_password" {
  length  = 16
  special = false
}
locals {
  wso_sql_usernames = [for s in var.wso_sql_data_schema : s.username]
  wso_sql_password  = random_password.wso_sql_password.result
}
module "wso_sql_user" {
  source = "../sql_user"
  count = length(local.wso_sql_usernames)
  
  instance_name = module.pgsql.name
  username      = local.wso_sql_usernames[count.index]
  password      = local.wso_sql_password
  
  depends_on = [module.pgsql]
}

# APP Username/Password
resource "random_password" "app_sql_password" {
  length  = 16
  special = false
}
locals {
  app_sql_usernames = [for s in var.app_sql_data_schema : s.username]
  app_sql_password  = random_password.app_sql_password.result
}
module "app_sql_user" {
  source = "../sql_user"
  count = length(local.app_sql_usernames)
  
  instance_name = module.pgsql.name
  username      = local.app_sql_usernames[count.index]
  password      = local.app_sql_password
  
  depends_on = [module.pgsql]
}

###
### SQL Databases
###
# WSO2 Database
module "wso_sql_database" {
  source = "../sql_database"
  
  instance_name = module.pgsql.name
  database      = var.wso_sql_database
  
  depends_on = [module.pgsql, module.wso_sql_user]
}

# APP Database
module "app_sql_database" {
  source = "../sql_database"
  
  instance_name = module.pgsql.name
  database      = var.app_sql_database
  
  depends_on = [module.pgsql, module.app_sql_user]
}

###
### SQL Import
###
# WSO2 SQL Import
locals {
  wso_import_sql_files  = [
    for s in var.wso_sql_data_schema : {
      file_name   = s.file_name
      local_path  = s.local_path
      database    = s.database
      import_user = s.username
    }
  ]
}
module "wso_sql_import" {
  source = "../sql_import"
  
  project_id               = var.project_id
  storage_name             = var.storage_sql_name
  storage_location         = var.storage_sql_location
  sql_instance_name        = module.pgsql.name
  sql_service_account_name = module.pgsql.service_account_name
  import_files             = local.wso_import_sql_files
  database_id              = module.wso_sql_database.id
  environment              = var.environment
  
  depends_on = [module.wso_sql_user]
}

# APP SQL Import
locals {
  app_import_sql_files  = [
    for s in var.app_sql_data_schema : {
      file_name   = s.file_name
      local_path  = s.local_path
      database    = s.database
      import_user = s.username
    }
  ]
}
module "app_sql_import" {
  source = "../sql_import"
  
  project_id               = var.project_id
  storage_name             = var.storage_sql_name
  storage_location         = var.storage_sql_location
  sql_instance_name        = module.pgsql.name
  sql_service_account_name = module.pgsql.service_account_name
  import_files             = local.app_import_sql_files
  database_id              = module.app_sql_database.id
  environment              = var.environment
  
  depends_on = [module.app_sql_user, module.wso_sql_import]
}

# Output
output "api_manager_ip_name" {
  value = (var.enable_ext_api_manager) ? google_compute_address.api_manager_ip[0].name : null
}
output "api_manager_ip_address" {
  value = (var.enable_ext_api_manager) ? google_compute_address.api_manager_ip[0].address : null
}
output "sql_connection_name" {
  value = module.pgsql.connection_name
}
output "wso_sql_password" {
  value = local.wso_sql_password
}
output "app_sql_password" {
  value = local.app_sql_password
}
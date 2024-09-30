# GCP Backend
terraform {
  backend "gcs" {}
}

###
### APIs
###
module "apis" {
  source = "../../../../modules/gcp/apis"
  
  project_id = var.project_id
  apis_list  = var.apis_list
}

###
### Network
###
module "network" {
  source = "../../../../modules/gcp/network"
  
  project_id            = var.project_id
  network_name          = var.network_name_prefix
  subnet_region         = var.region
  subnet_cidr_range     = var.subnet_cidr_range
  google_managed_range  = var.google_managed_range
  google_managed_length = var.google_managed_length
  natgw_manual_ip_count = var.natgw_manual_ip_count
  environment           = var.environment_sufix
  
  # Requires enable the API service before creation
  depends_on = [module.apis]
}

###
### SQL
###
module "pgsql" {
  source = "../../../../modules/gcp/sql"
  
  project_id       = var.project_id
  region           = var.region
  name_prefix      = var.sql_instance_name_prefix
  database_version = var.sql_database_version
  instance_type    = var.sql_instance_type
  network_id       = module.network.network_id
  instance_flags   = var.sql_instance_flags
  environment      = var.environment_sufix
  
  # Requires enable the API service and Network before creation
  depends_on = [module.apis, module.network]
}

###
### SQL Database
###
# Database
module "sql_database" {
  source = "../../../../modules/gcp/sql_database"
  
  instance_name = module.pgsql.name
  database      = var.sql_database
  
  # Requires enable the API service before creation
  depends_on = [module.apis]
}

###
### SQL User
###
# Username
resource "random_password" "app_sql_password" {
  length  = 16
  special = false
}
module "sql_user" {
  source = "../../../../modules/gcp/sql_user"
  
  instance_name = module.pgsql.name
  username      = var.sql_username
  password      = random_password.app_sql_password.result
  
  # Requires enable the API service before creation
  depends_on = [module.apis]
}

###
### GKE
###
module "gke" {
  source = "../../../../modules/gcp/kubernetes"
  
  project_id        = var.project_id
  network_id        = module.network.network_id
  subnet_id         = module.network.subnet_id
  subnet_cidr_range = var.subnet_cidr_range
  name              = var.gke_cluster_name
  location          = var.gke_location
  subnet_pods       = var.gke_subnet_pods
  subnet_services   = var.gke_subnet_services
  subnet_master     = var.gke_subnet_master
  release_channel   = var.gke_release_channel
  master_version    = var.gke_master_version
  min_node_count    = var.gke_min_node_count
  max_node_count    = var.gke_max_node_count
  machine_type      = var.gke_machine_type
  master_authorized_networks = var.gke_master_authorized_networks
  environment       = var.environment_sufix
  
  # Requires enable the API service before creation
  depends_on = [module.apis]
}

###
### Storage
###
module "frontend" {
  source = "../../../../modules/gcp/storage"
  
  project_id     = var.project_id
  name           = var.storage_portal_name
  location       = var.storage_portal_location
  uniform_access = true
  environment    = var.environment_sufix
  
  # Requires enable the API service before creation
  depends_on = [module.apis]
}

###
### Cloud Armor
###
module "armor" {
  source = "../../../../modules/gcp/armor"
  
  project_id     = var.project_id
  name           = var.armor_policy_name
  description    = var.armor_policy_description
  default_action = var.armor_default_action
  rules          = var.armor_rules
  environment    = var.environment_sufix
  
  # Requires enable the API service before creation
  depends_on = [module.apis]
}

###
### Cloud memorystore for redis
###
module "memorystore" {
  source = "../../../../modules/gcp/memorystore"


  project_id            = var.project_id
  google_managed_range  = var.google_managed_range
  google_managed_length = var.google_managed_length
  name_redis            = var.name_redis
  tier_type             = var.tier_type
  memory_size           = var.memory_size
  region_id             = var.region_id
  connect_mode          = var.connect_mode
  redis_version         = var.redis_version
  auth_enable           = var.auth_enable
  display_name          = var.display_name
  environment_sufix     = var.environment_sufix

  depends_on = [module.apis]
}

###
### Secret manager GCP
###
module "secret_manager" {
  source = "../../../../modules/gcp/secret_manager"
 
  value               = module.memorystore.auth_string
  secret_id           = var.secret_id
  label               = var.label
  location_1          = var.location_1
  location_2          = var.location_2
  key                 = var.key      

  depends_on = [module.apis, module.memorystore]
}
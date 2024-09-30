# Variables
project_id                = "app-client1"
region                    = "us-east1"
terraform_service_account = "terraform@xxxxx.iam.gserviceaccount.com"
environment_sufix         = "dev"

# APIs
apis_list = [
  "iam.googleapis.com",
  "storage.googleapis.com",
  "servicenetworking.googleapis.com",
  "compute.googleapis.com",
  "container.googleapis.com",
  "artifactregistry.googleapis.com",
  "sqladmin.googleapis.com",
  "secretmanager.googleapis.com",
  "dns.googleapis.com",
  "redis.googleapis.com",
]

# Network
network_name_prefix       = "client1-client-vpc"
subnet_cidr_range         = "10.163.211.0/24"
google_managed_range      = "10.163.624.0"
google_managed_length     = 21
natgw_manual_ip_count     = 0

# SQL
sql_instance_name_prefix  = "pgsql-client1"
sql_database_version      = "POSTGRES_13"
sql_instance_type         = "db-g1-small"
sql_database              = "client1"
sql_username              = "client1_user"
sql_instance_flags        = [{
  name  = "max_connections"
  value = "500"
},
{
  name  = "log_checkpoints"
  value = "on"
},
{
  name  = "log_connections"
  value = "on"
},
{
  name  = "log_disconnections"
  value = "on"
},
{
  name  = "log_duration"
  value = "on"
}]

# GKE
gke_cluster_name          = "client1-cluster"
gke_location              = "us-east1-b"
gke_subnet_pods           = "10.10.10.0/20"
gke_subnet_services       = "10.10.4.0/24"
gke_subnet_master         = "10.10.8.0/28"
gke_release_channel       = "STABLE"
gke_master_version        = "1.21.5-gke.1802"
gke_min_node_count        = 2
gke_max_node_count        = 3
gke_machine_type          = "e2-standard-4"
gke_master_authorized_networks = [
  {
    cidr_block   = "111.111.222.0/18"
    display_name = "group 1"
  },
  {
    cidr_block   = "111.111.111.111/32"
    display_name = "group3"
  },
  {
    cidr_block   = "222.229.222.222/32"
    display_name = "user3"
  },
  {
    cidr_block   = "187.222.222.222/32"
    display_name = "user1"
  },
]

# Storage
storage_portal_name       = "public-portal"
storage_portal_location   = "US"

# Cloud Armor
armor_policy_name         = "client1-cloud-armor-policy"
armor_policy_description  = "client1 Cloud Armor Policy"
armor_default_action      = "deny(403)"
armor_rules               = [
  {
    action        = "allow"
    priority      = 1000
    description   = "group1"
    src_ip_ranges = "170.251.111.222/18,521.721.215.128/32"
  },
]

# Memory store
name_redis          = "redis-client1"
tier_type           = "STANDARD_HA"
memory_size         = "1"
region_id           = "us-east1-b"
connect_mode        = "PRIVATE_SERVICE_ACCESS"
redis_version       = "REDIS_5_0"
auth_enable         = "true"
display_name        = "Redis Instance"


# Secret Manager
secret_id           = "microservice-redis-gke-secret"
label               = "microservice-redis-gke-secret"
location_1          = "us-east1"
location_2          = "us-central1"
key                 = "spring.redis.password"
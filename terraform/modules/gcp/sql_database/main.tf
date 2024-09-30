###
### Database
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
variable "instance_name" {}
variable "database" {}

# Database
resource "google_sql_database" "db" {
  instance = var.instance_name
  name     = var.database
}

# Output
output "id" {
  value = google_sql_database.db.id
}
output "name" {
  value = google_sql_database.db.name
}
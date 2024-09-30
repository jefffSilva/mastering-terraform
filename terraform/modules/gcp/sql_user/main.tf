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
variable "username" {}
variable "password" {
  type      = string
  sensitive = true
}

# Username
resource "google_sql_user" "user" {
  instance = var.instance_name
  name     = var.username
  password = var.password
}

# Output
output "password" {
  value = google_sql_user.user.password
}
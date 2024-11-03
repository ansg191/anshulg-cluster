terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.9.0"
    }
  }
}

data "google_project" "default" {
  project_id = "anshulg-cluster"
}

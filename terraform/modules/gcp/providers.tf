terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.47.0"
    }
  }
}

data "google_project" "default" {
  project_id = "anshulg-cluster"
}

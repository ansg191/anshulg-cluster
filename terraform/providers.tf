terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.37.0"
    }
  }
}

provider "google" {
  project = "anshulg-cluster"
  region  = "us-west1"
  zone    = "us-west1-a"
}

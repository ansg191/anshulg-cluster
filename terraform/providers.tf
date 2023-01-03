terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.47.0"
    }
  }
}

provider "google" {
  project = "anshulg-cluster"
  region  = "us-west1"
  zone    = "us-west1-a"
}
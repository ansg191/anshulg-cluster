resource "google_service_account" "default" {
  account_id   = "cluster-service-account"
  display_name = "Cluster Service Account"
}

resource "google_container_cluster" "default" {
  name     = "default"
  location = "us-west1-a"

  remove_default_node_pool = true
  initial_node_count       = 1
}

resource "google_container_node_pool" "default_spot_pool" {
  name       = "default-spot-pool"
  cluster    = google_container_cluster.default.name
  node_count = 1

  node_config {
    preemptible  = true
    machine_type = "e2-standard-2"

    service_account = google_service_account.default.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }
}

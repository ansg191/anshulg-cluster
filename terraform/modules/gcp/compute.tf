# region E2-Medium us-west1-a

# resource "google_compute_reservation" "e2-medium" {
#   name = "gke-reservation-frqbi"
#   zone = "us-west1-a"

#   specific_reservation {
#     count = 2
#     instance_properties {
#       machine_type = "e2-medium"
#     }
#   }

#   specific_reservation_required = true
# }

# Create CUD for node
# resource "google_compute_region_commitment" "e2-standard-2" {
#   name       = "cud-us-west1-e2-standard-2"
#   plan       = "TWELVE_MONTH"
#   category   = "MACHINE"
#   type       = "GENERAL_PURPOSE_E2"
#   auto_renew = true

#   resources {
#     type   = "VCPU"
#     amount = "2"
#   }
#   resources {
#     type   = "MEMORY"
#     amount = "8"
#   }

#   existing_reservations = google_compute_reservation.e2-standard-2.id
# }

# Create node pool for the CUD reservation
# resource "google_container_node_pool" "default_pool" {
#   name       = "default-cud-pool"
#   cluster    = google_container_cluster.default.id
#   node_count = 2

#   node_config {
#     preemptible  = false
#     machine_type = "e2-medium"

#     service_account = google_service_account.default.email
#     oauth_scopes = [
#       "https://www.googleapis.com/auth/cloud-platform",
#     ]

#     workload_metadata_config {
#       mode = "GKE_METADATA"
#     }

#     reservation_affinity {
#       consume_reservation_type = "SPECIFIC_RESERVATION"
#       key                      = "compute.googleapis.com/reservation-name"
#       values                   = [google_compute_reservation.e2-medium.name]
#     }
#   }

#   management {
#     auto_upgrade = true
#   }
# }

# endregion E2-Medium us-west1-a
# region E2-standard-2 us-west1-b

resource "google_compute_reservation" "e2-standard-b" {
  name = "gke-reservation-rvctu"
  zone = "us-west1-b"

  specific_reservation {
    count = 1
    instance_properties {
      machine_type = "e2-standard-2"
    }
  }

  specific_reservation_required = true
}

resource "google_container_node_pool" "default_pool_b" {
  name       = "default-cud-pool-b"
  cluster    = google_container_cluster.default.id
  node_count = 2
  location   = "us-west1-b"

  node_config {
    preemptible  = false
    machine_type = "e2-standard-2"

    service_account = google_service_account.default.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    reservation_affinity {
      consume_reservation_type = "SPECIFIC_RESERVATION"
      key                      = "compute.googleapis.com/reservation-name"
      values                   = [google_compute_reservation.e2-standard-b.name]
    }
  }

  management {
    auto_upgrade = true
  }

  depends_on = [
    google_compute_reservation.e2-standard-b
  ]
}

# endregion E2-standard-2 us-west1-b

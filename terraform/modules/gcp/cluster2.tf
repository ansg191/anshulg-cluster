resource "google_container_cluster" "region" {
	name     = "region"
	location = "us-west2"

	remove_default_node_pool = true
	initial_node_count       = 1

	datapath_provider  = "ADVANCED_DATAPATH"
	logging_service    = "none"
	monitoring_service = "none"

	workload_identity_config {
		workload_pool = "${data.google_project.default.project_id}.svc.id.goog"
	}

	# SNYK-CC-TF-87
	master_auth {
		client_certificate_config {
			issue_client_certificate = false
		}
	}

	addons_config {
		gcs_fuse_csi_driver_config {
			enabled = true
		}
	}

	gateway_api_config {
		channel = "CHANNEL_STANDARD"
	}
}

resource "google_container_node_pool" "region_spot_pool" {
	name       = "default-spot-pool"
	cluster    = google_container_cluster.region.id
	node_count = 1

	node_config {
		preemptible  = true
		machine_type = "e2-standard-2"

		service_account = google_service_account.default.email
		oauth_scopes = [
			"https://www.googleapis.com/auth/cloud-platform",
		]

		workload_metadata_config {
			mode = "GKE_METADATA"
		}
	}

	management {
		auto_upgrade = true
	}
}

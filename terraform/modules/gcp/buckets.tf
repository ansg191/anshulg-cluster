resource "google_storage_bucket" "gke-test-bucket" {
	name          = "gke-test-bucket-lvmn"
	location      = "US"
	force_destroy = true

	storage_class            = "STANDARD"
	public_access_prevention = "enforced"
}

resource "google_storage_bucket_iam_member" "gke-test-bucket-default" {
	bucket = google_storage_bucket.gke-test-bucket.name
	member = "principal://iam.googleapis.com/projects/${data.google_project.default.number}/locations/global/workloadIdentityPools/${data.google_project.default.project_id}.svc.id.goog/subject/ns/default/sa/default"
	role   = "roles/storage.objectUser"
}

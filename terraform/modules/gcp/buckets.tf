# GKE Buckets

# Test GKE Bucket
resource "google_storage_bucket" "gke-test-bucket" {
	name          = "gke-test-bucket-lvmn"
	location      = "US"
	force_destroy = true

	uniform_bucket_level_access = true
	storage_class               = "STANDARD"
	public_access_prevention    = "enforced"
}

# Bind GKE Bucket to default service account in the default namespace
resource "google_storage_bucket_iam_member" "gke-test-bucket-default" {
	bucket = google_storage_bucket.gke-test-bucket.name
	member = "principal://iam.googleapis.com/projects/${data.google_project.default.number}/locations/global/workloadIdentityPools/${data.google_project.default.project_id}.svc.id.goog/subject/ns/default/sa/default"
	role   = "roles/storage.objectUser"
}

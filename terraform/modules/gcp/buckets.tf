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

# Backup GKE Bucket
resource "google_storage_bucket" "gke-backup-bucket" {
	name          = "restic-backup-bucket-9r6c"
	location      = "US"
	force_destroy = false

	uniform_bucket_level_access = true
	storage_class               = "STANDARD"
	public_access_prevention    = "enforced"

	hierarchical_namespace {
		enabled = true
	}
}

# Bind GKE Bucket to restic service account in the restic  namespace
resource "google_storage_bucket_iam_member" "gke-backup-bucket-restic" {
	bucket = google_storage_bucket.gke-backup-bucket.name
	member = "principal://iam.googleapis.com/projects/${data.google_project.default.number}/locations/global/workloadIdentityPools/${data.google_project.default.project_id}.svc.id.goog/subject/ns/restic/sa/restic"
	role   = "roles/storage.objectUser"
}

# Cockroach Backup Bucket
resource "google_storage_bucket" "gke-cockroach-bucket" {
	name     = "cockroacchdb-backup-bucket-8kmcx"
	location = "US"
	force_destroy = false

	uniform_bucket_level_access = true
	storage_class = "COLDLINE"
	public_access_prevention = "enforced"
}

# Bind GKE bucket to cockroachdb-sa service account in the miniflux namespace
resource "google_storage_bucket_iam_member" "gke-cockroach-bucket-miniflux" {
	bucket = google_storage_bucket.gke-cockroach-bucket.name
	member = "principal://iam.googleapis.com/projects/${data.google_project.default.number}/locations/global/workloadIdentityPools/${data.google_project.default.project_id}.svc.id.goog/subject/ns/miniflux/sa/cockroachdb-sa"
	role   = "roles/storage.objectUser"
}

resource "google_storage_bucket" "gke-test-bucket" {
	name          = "gke-test-bucket-lvmn"
	location      = "US"
	force_destroy = true

	storage_class            = "STANDARD"
	public_access_prevention = "enforced"
}

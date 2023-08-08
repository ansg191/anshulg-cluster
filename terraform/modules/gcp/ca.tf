resource "google_privateca_ca_pool" "default" {
	name     = "default"
	location = "us-west1"
	tier     = "DEVOPS"
	publishing_options {
		publish_ca_cert = true
		publish_crl     = false
	}
	issuance_policy {
		maximum_lifetime = "2592000s"
	}
}

# Setup for anshulg.direct DNS rebinding

# DNS zone
data "google_dns_managed_zone" "direct" {
	name = "anshulg-direct"
}

# Service account for cert-manager
resource "google_service_account" "dns01-solver" {
	account_id = "dns01-solver"
}

# Give the service account the ability to manage the DNS zone
resource "google_dns_managed_zone_iam_binding" "dns01-solver-admin" {
	managed_zone = data.google_dns_managed_zone.direct.name
	role         = "roles/dns.admin"
	members = [
		"serviceAccount:${google_service_account.dns01-solver.email}"
	]
}

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
resource "google_project_iam_binding" "dns_admin" {
	project = data.google_project.default.project_id
	role    = "roles/dns.admin"
	members = [
		"serviceAccount:${google_service_account.dns01-solver.email}"
	]
}

# Add DNS record to 192.168.1.100
resource "google_dns_record_set" "normal" {
	managed_zone = data.google_dns_managed_zone.direct.name
	name         = data.google_dns_managed_zone.direct.dns_name
	type         = "A"
	ttl          = 60
	rrdatas = [
		"192.168.1.100"
	]
}

# Add wildcard DNS record to 192.168.1.100
resource "google_dns_record_set" "wildcard" {
	managed_zone = data.google_dns_managed_zone.direct.name
	name         = "*.${data.google_dns_managed_zone.direct.dns_name}"
	type         = "A"
	ttl          = 60
	rrdatas = [
		"192.168.1.100"
	]
}

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
resource "google_dns_managed_zone_iam_member" "direct-dns-admin" {
	managed_zone = data.google_dns_managed_zone.direct.name
	member       = "serviceAccount:${google_service_account.dns01-solver.email}"
	role         = "roles/dns.admin"
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

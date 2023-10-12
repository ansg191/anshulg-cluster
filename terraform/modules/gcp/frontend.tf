resource "google_certificate_manager_certificate" "default" {
	name        = "default"
	description = "The default certificate"
	location    = "global"
	scope       = "ALL_REGIONS"
	managed {
		domains = [
			google_certificate_manager_dns_authorization.base.domain,
			"*.${google_certificate_manager_dns_authorization.base.domain}"
		]
		dns_authorizations = [
			google_certificate_manager_dns_authorization.base.id
		]
	}
}

resource "google_certificate_manager_dns_authorization" "base" {
	name   = "anshulg-base"
	domain = "anshulg.com"
}

resource "google_dns_record_set" "cert-cname" {
	name         = google_certificate_manager_dns_authorization.base.dns_resource_record[0].name
	managed_zone = "anshulg-com"
	type         = google_certificate_manager_dns_authorization.base.dns_resource_record[0].type
	ttl          = 300
	rrdatas      = [google_certificate_manager_dns_authorization.base.dns_resource_record[0].data]
}

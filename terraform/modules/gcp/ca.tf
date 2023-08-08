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

resource "google_privateca_certificate_authority" "default" {
  pool                     = google_privateca_ca_pool.default.name
  location                 = "us-west1"
  certificate_authority_id = "anshulg-ca"
  config {
    subject_config {
      subject {
        common_name  = "Anshul Gupta Root CA"
        organization = "Anshul Gupta"
        province     = "California"
        country_code = "US"
      }
    }
    x509_config {
      ca_options {
        is_ca = true
      }
      key_usage {
        base_key_usage {
          cert_sign = true
          crl_sign = true
        }
        extended_key_usage {
          server_auth = false
        }
      }
    }
  }
  key_spec {
    algorithm = "EC_P384_SHA384"
  }
  lifetime = "315360000s"
}

resource "google_compute_firewall" "http_api" {
  project = var.gcp_project_id

  name    = "default-allow-vault"
  network = "default"

  allow {
    protocol = "tcp"

    ports = [
      "8200",
    ]
  }

  target_tags   = ["default-vault"]
  source_ranges = ["0.0.0.0/0"]
}
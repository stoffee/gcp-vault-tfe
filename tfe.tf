resource "google_compute_instance" "tfe" {
  name         = "${var.prefix}-tfe"
  machine_type     = var.tfe_cluster_machine_type
  zone         = var.gcloud_zone

tags = [
    "${var.prefix}-tfe",
  ]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-minimal-1804-lts"
    }
  }

  # Local SSD disk
#  scratch_disk {
#  }

  network_interface {
    network = "default"
#    network = "${var.network}"

    access_config {
      # Ephemeral IP
    }
  }

  allow_stopping_for_update = true

  # Service account with Cloud KMS roles for the Compute Instance
  service_account {
    email  = google_service_account.tfe_kms_service_account.email
    scopes = ["cloud-platform", "compute-rw", "userinfo-email", "storage-ro"]
  }

  metadata_startup_script = <<SCRIPT
    sudo apt-get install -y unzip libtool libltdl-dev

SCRIPT

}

output "project" {
  value = google_compute_instance.tfe.project
}

output "tfe_server_instance_id" {
  value = google_compute_instance.tfe.self_link
}
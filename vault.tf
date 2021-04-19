provider "google" {
  region      = var.gcp_region
  credentials = var.gcp_credentials
  project     = var.gcp_project_id
}

resource "google_service_account" "vault_kms_service_account" {
  account_id   = "${var.prefix}-gcpkms"
  display_name = "Vault KMS for auto-unseal"
}

resource "google_compute_instance" "vault" {
  name         = "${var.prefix}-vault"
  machine_type     = var.vault_cluster_machine_type
  zone         = var.gcloud_zone

tags = [
    "${var.prefix}-vault",
  ]

  boot_disk {
    initialize_params {
      size = 100
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
    email  = google_service_account.vault_kms_service_account.email
    scopes = ["cloud-platform", "compute-rw", "userinfo-email", "storage-ro"]
  }

  metadata_startup_script = <<SCRIPT
    sudo timedatectl set-timezone US/Pacific
    sudo apt update
    sudo apt-get install -y unzip libtool libltdl-dev

    curl -s -L -o ~/vault.zip ${var.vault_url}
    sudo unzip ~/vault.zip
    sudo install -c -m 0755 vault /usr/bin

    sudo mkdir -p /opt/vault/storage
    touch /opt/vault/vault.unseal.info /opt/vault/setup.log
    chmod 777 /opt/vault/vault.unseal.info /opt/vault/setup.log

    sudo echo -e '[Unit]\nDescription="HashiCorp Vault - A tool for managing secrets"\nDocumentation=https://www.vaultproject.io/docs/\nRequires=network-online.target\nAfter=network-online.target\n\n[Service]\nExecStart=/usr/bin/vault server -config=/opt/vault/config.hcl\nExecReload=/bin/kill -HUP $MAINPID\nKillMode=process\nKillSignal=SIGINT\nRestart=on-failure\nRestartSec=5\n\n[Install]\nWantedBy=multi-user.target\n' > /lib/systemd/system/vault.service

    sudo echo -e 'storage "file" {\n  path = "/opt/vault/storage"\n}\n\nlistener "tcp" {\n  address     = "0.0.0.0:8200"\n  tls_disable = 1\n}\n\nseal "gcpckms" {\n  project     = "${var.gcp_project_id}"\n  region      = "${var.keyring_location}"\n  key_ring    = "${var.keyring_name}"\n  crypto_key  = "${var.crypto_key}"\n}\n\ndisable_mlock = true\n' > /opt/vault/config.hcl

    sudo chmod 0664 /lib/systemd/system/vault.service

    sudo echo -e 'alias v="vault"\nalias vault="vault"\nexport VAULT_ADDR="http://127.0.0.1:8200"\n' > /etc/profile.d/vault.sh

    source /etc/profile.d/vault.sh

    sudo systemctl enable vault
    sudo systemctl start vault

    sleep 10

    /usr/bin/vault operator init -recovery-shares=1 -recovery-threshold=1 >> /opt/vault/vault.unseal.info

    ROOT_TOKEN=`cat /opt/vault/vault.unseal.info |grep Root|awk '{print $4}'`
    /usr/bin/vault login $ROOT_TOKEN >> /opt/vault/setup.log
    /usr/bin/vault secrets enable -path=sercets kv2 >> /opt/vault/setup.log
    /usr/bin/vault auth enable gcp >>/opt/vault/setup.log
    /usr/bin/vault write auth/gcp/role/my-iam-role type="iam"  policies="dev,prod"  bound_service_accounts="${var.bound_service_account}" >>/opt/vault/setup.log
    /usr/bin/vault write auth/gcp/role/my-gce-role type="gce"  policies="dev,prod" bound_projects="${var.gcp_project_id}" >>/opt/vault/setup.log
    /usr/bin/vault enable gcp >>/opt/vault/setup.log
    /usr/bin/vault vault write gcp/config credentials=${var.gcp_iam_vault_service_account} >>/opt/vault/setup.log
    vault write gcp/roleset/my-token-roleset \
    project="my-project" \
    secret_type="access_token"  \
    token_scopes="https://www.googleapis.com/auth/cloud-platform" \
    bindings=-<<B0F
      resource "//cloudresourcemanager.googleapis.com/projects/${var.gcp_project_id}" {
        roles = ["roles/viewer"]
      }
    B0F
SCRIPT

}

output "project" {
  value = google_compute_instance.vault.project
}

output "vault_server_instance_id" {
  value = google_compute_instance.vault.self_link
}

 #Create a KMS key ring
 resource "google_kms_key_ring" "key_ring" {
   project  = var.gcp_project_id
   name     = var.keyring_name
   location = var.keyring_location
 }

# Create a crypto key for the key ring
 resource "google_kms_crypto_key" "crypto_key" {
   name            = var.crypto_key
   key_ring        = google_kms_key_ring.key_ring.self_link
   rotation_period = "100000s"
 }

# Add the service account to the Keyring
resource "google_kms_key_ring_iam_binding" "vault_iam_kms_binding" {
   key_ring_id = google_kms_key_ring.key_ring.id
#  key_ring_id = "${var.gcp_project_id}/${var.keyring_location}/${var.keyring_name}"
  role = "roles/owner"

  members = [
    "serviceAccount:${google_service_account.vault_kms_service_account.email}",
  ]
}

# Google Cloud Provider
# https://www.terraform.io/docs/providers/google/index.html

provider "google" {
  #  version = "1.17.1"
}

provider "kubernetes" {
  #  version  = "1.2"
  host     = "${google_container_cluster.gocd_cluster.endpoint}"
  username = "${google_container_cluster.gocd_cluster.master_auth.0.username}"
  password = "${google_container_cluster.gocd_cluster.master_auth.0.password}"

  client_certificate     = "${base64decode(google_container_cluster.gocd_cluster.master_auth.0.client_certificate)}"
  client_key             = "${base64decode(google_container_cluster.gocd_cluster.master_auth.0.client_key)}"
  cluster_ca_certificate = "${base64decode(google_container_cluster.gocd_cluster.master_auth.0.cluster_ca_certificate)}"
}

# Project Resource
# https://www.terraform.io/docs/providers/google/r/google_project.html

resource "google_project" "gocd_project" {
  name            = "${var.project}"
  project_id      = "${var.project}"
  billing_account = "${var.billing_id}"
  folder_id       = "folders/${var.folder_id}"
}

# Project Services Resource
# Note: This resource attempts to be the authoritative source on all enabled APIs
# https://www.terraform.io/docs/providers/google/r/google_project_services.html

resource "google_project_services" "gocd_apis" {
  project            = "${google_project.gocd_project.project_id}"
  disable_on_destroy = false

  services = [
    "dns.googleapis.com",
    "cloudkms.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "container.googleapis.com",
    "containerregistry.googleapis.com",
    "stackdriver.googleapis.com",
    "websecurityscanner.googleapis.com",
    "compute.googleapis.com",
    "pubsub.googleapis.com",
    "oslogin.googleapis.com",
    "bigquery-json.googleapis.com",
    "cloudapis.googleapis.com",
    "clouddebugger.googleapis.com",
    "cloudtrace.googleapis.com",
    "datastore.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "servicemanagement.googleapis.com",
    "serviceusage.googleapis.com",
    "sql-component.googleapis.com",
    "storage-api.googleapis.com",
    "storage-component.googleapis.com",
  ]
}

# IAM Policy for Projects Resource
# https://www.terraform.io/docs/providers/google/r/google_project_iam.html#google_project_iam_member

# This allows external dns to modify records in the dns project 

resource "google_project_iam_member" "gocd_dns_project_iam" {
  project = "${var.dns_project}"
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_project.gocd_project.number}-compute@developer.gserviceaccount.com"

  depends_on = ["google_project_services.gocd_apis"]
}

# Kubernetes Engine (GKE) Resource
# https://www.terraform.io/docs/providers/google/r/container_cluster.html

resource "google_container_cluster" "gocd_cluster" {
  name    = "gocd-cluster-${var.zone}"
  project = "${google_project.gocd_project.project_id}"
  zone    = "${var.zone}"

  min_master_version = "${var.kubernetes_version}"
  node_version       = "${var.kubernetes_version}"
  logging_service    = "${var.kubernetes_logging_service}"
  monitoring_service = "${var.kubernetes_monitoring_service}"

  node_pool {
    name = "default-pool"

    node_config {
      machine_type = "${var.machine_type}"

      oauth_scopes = [
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/compute",
        "https://www.googleapis.com/auth/devstorage.read_write",
        "https://www.googleapis.com/auth/logging.write",
        "https://www.googleapis.com/auth/monitoring",
      ]
    }

    initial_node_count = "${var.node_count}"

    autoscaling {
      min_node_count = "${var.min_node_count}"
      max_node_count = "${var.max_node_count}"
    }

    management {
      auto_repair  = "true"
      auto_upgrade = "false"
    }
  }

  depends_on = ["google_project_services.gocd_apis"]
}

# Compute Disk Resource
# https://www.terraform.io/docs/providers/google/r/compute_disk.html

resource "google_compute_disk" "gocd_disk" {
  name    = "godata"
  project = "${google_project.gocd_project.project_id}"
  size    = "50"
  zone    = "${var.zone}"

  depends_on = ["google_project_services.gocd_apis"]
}

# Template File Data Source
# https://www.terraform.io/docs/providers/template/d/file.html

data "template_file" "external_dns" {
  template = "${file("${path.module}/../k8s/external-dns.yaml")}"

  vars {
    dns_project = "${var.dns_project}"
  }
}

data "template_file" "cert_manager" {
  template = "${file("${path.module}/../k8s/cert-manager.yaml")}"

  vars {
    lets_encrypt_api   = "${var.lets_encrypt_api}"
    lets_encrypt_email = "${var.lets_encrypt_email}"
  }
}

data "template_file" "temp_tls" {
  template = "${file("${path.module}/../k8s/temp-tls.yaml")}"
}

data "template_file" "gocd" {
  template = "${file("${path.module}/../k8s/gocd.yaml")}"

  vars {
    domain = "${var.domain}"
    host   = "${var.host}"
  }
}

# Null Resource
# https://www.terraform.io/docs/providers/null/resource.html

resource "null_resource" "external_dns" {
  triggers {
    config_sha1 = "${sha1(data.template_file.external_dns.rendered)}"
  }

  provisioner "local-exec" {
    command = <<EOF
gcloud container clusters get-credentials "${google_container_cluster.gocd_cluster.name}" --zone="${google_container_cluster.gocd_cluster.zone}" --project="${google_container_cluster.gocd_cluster.project}"

CONTEXT="gke_${google_container_cluster.gocd_cluster.project}_${google_container_cluster.gocd_cluster.zone}_${google_container_cluster.gocd_cluster.name}"

ACCOUNT=$(gcloud info --format='value(config.account)')

kubectl create --context="$CONTEXT" clusterrolebinding cluster-admin-binding --clusterrole cluster-admin --user $ACCOUNT

echo '${data.template_file.external_dns.rendered}' | kubectl apply --context="$CONTEXT" -f -

for i in $(seq -s " " 1 15); do
  sleep $i
  if [ $(kubectl get pod --namespace=external-dns | grep external-dns | grep Running | wc -l) -eq 1 ]; then
    echo "Pods are running"
    exit 0
  fi
done

echo "Pods are not ready after 2m"
exit 1
    EOF
  }
}

resource "null_resource" "cert_manager" {
  triggers {
    config_sha1 = "${sha1(data.template_file.cert_manager.rendered)}"
  }

  provisioner "local-exec" {
    command = <<EOF
gcloud container clusters get-credentials "${google_container_cluster.gocd_cluster.name}" --zone="${google_container_cluster.gocd_cluster.zone}" --project="${google_container_cluster.gocd_cluster.project}"

CONTEXT="gke_${google_container_cluster.gocd_cluster.project}_${google_container_cluster.gocd_cluster.zone}_${google_container_cluster.gocd_cluster.name}"

ACCOUNT=$(gcloud info --format='value(config.account)')

kubectl create --context="$CONTEXT" clusterrolebinding cluster-admin-binding --clusterrole cluster-admin --user $ACCOUNT

echo '${data.template_file.cert_manager.rendered}' | kubectl apply --context="$CONTEXT" -f -

for i in $(seq -s " " 1 15); do
  sleep $i
  if [ $(kubectl get pod --namespace=cert-manager | grep cert-manager | grep Running | wc -l) -eq 1 ]; then
    echo "Pods are running"
    exit 0
  fi
done

echo "Pods are not ready after 2m"
exit 1
    EOF
  }
}

resource "null_resource" "gocd" {
  triggers {
    config_sha1 = "${sha1(data.template_file.gocd.rendered)}"
  }

  provisioner "local-exec" {
    command = <<EOF
gcloud container clusters get-credentials "${google_container_cluster.gocd_cluster.name}" --zone="${google_container_cluster.gocd_cluster.zone}" --project="${google_container_cluster.gocd_cluster.project}"

CONTEXT="gke_${google_container_cluster.gocd_cluster.project}_${google_container_cluster.gocd_cluster.zone}_${google_container_cluster.gocd_cluster.name}"

echo '${data.template_file.gocd.rendered}' | kubectl apply --context="$CONTEXT" -f -

for i in $(seq -s " " 1 15); do
  sleep $i
  if [ $(kubectl get pod --namespace=gocd | grep gocd | grep Running | wc -l) -eq 1 ]; then
    echo "Pods are Running"
    exit 0
  fi
done

echo "Pods are not ready after 2m"
exit 1
    EOF
  }

  depends_on = [
    "null_resource.external_dns",
  ]
}

output "gocd_url" {
  value = "https://${var.host}.${var.domain}"
}

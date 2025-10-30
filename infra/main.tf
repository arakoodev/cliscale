# Enable required APIs
resource "google_project_service" "apis" {
  project = var.project_id

  for_each = toset([
    "container.googleapis.com",
    "sqladmin.googleapis.com",
    "artifactregistry.googleapis.com",
    "servicenetworking.googleapis.com",
    "compute.googleapis.com"
  ])
  service                    = each.key
  disable_on_destroy         = false
    lifecycle {
    prevent_destroy = false
    #ignore_changes = [service]
  }
}

# VPC Network for GKE and Cloud SQL
resource "google_compute_network" "main" {
  name                    = "ws-cli-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.apis]
}

# Subnet for GKE
resource "google_compute_subnetwork" "gke_subnet" {
  name          = "gke-subnet"
  ip_cidr_range = "10.10.0.0/24"
  network       = google_compute_network.main.id
  region        = var.region
}

# VPC Peering for Cloud SQL Private IP
resource "google_compute_global_address" "private_ip_alloc" {
  name          = "google-managed-services-ws-cli-vpc"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "vpc_peering" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]
}

# Cloud NAT Gateway attached the VPC network GKE (Make sure gke cluster can call internet access update dependencies)
resource "google_compute_router" "router" {
  name    = "ws-cli-router"
  network = google_compute_network.main.id
  region = var.region
}
resource "google_compute_router_nat" "nat" {
  name                               = "ws-cli-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# GKE Autopilot Cluster (Private)
resource "google_container_cluster" "primary" {
  name       = var.cluster_name
  location   = var.region
  network    = google_compute_network.main.id
  subnetwork = google_compute_subnetwork.gke_subnet.id

  deletion_protection = false

  private_cluster_config {
    enable_private_nodes = true
    enable_private_endpoint = false # Controller/Gateway will be exposed via GCLB Ingress
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  networking_mode = "VPC_NATIVE"

  master_authorized_networks_config {
    # Correctly finding the public IPs need to whitelist access gke cluster to deploy anything.
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "admin"
    }
  }

  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "10.20.0.0/20"
    services_ipv4_cidr_block = "10.30.0.0/20"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }


  # Use Autopilot
  enable_autopilot = true

  depends_on = [google_service_networking_connection.vpc_peering]
}

resource "time_sleep" "wait_for_network" {
  depends_on = [google_service_networking_connection.vpc_peering]
  create_duration = "300s"
}


# Cloud SQL for PostgreSQL (Private IP)
resource "google_sql_database_instance" "main" {
  name             = var.sql_instace_name
  database_version = var.sql_database_version
  region           = var.region

  deletion_protection = false

  settings {
    tier = "db-g1-small"
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.main.id
    }
    backup_configuration {
      enabled = true
    }
    location_preference {
      zone = "${var.region}-a"
    }
  }

  depends_on = [google_service_networking_connection.vpc_peering]
}

resource "google_sql_database" "main" {
  name     = var.db_name
  instance = google_sql_database_instance.main.name
}

resource "google_sql_user" "main" {
  name     = var.db_user
  instance = google_sql_database_instance.main.name
  password = var.db_password
}

# Artifact Registry for container images
resource "google_artifact_registry_repository" "main" {
  location      = var.region
  repository_id = "apps"
  description   = "Container images for the ws-cli application"
  format        = "DOCKER"

  cleanup_policies {
    id     = "delete-untagged-images-after-7-days"
    action = "DELETE"
    condition {
      tag_state    = "UNTAGGED"
      older_than   = "604800s" # 7 days
    }
  }
  depends_on = [google_project_service.apis]
}

resource "google_service_account" "controller" {
  project      = var.project_id
  account_id   = "ws-cli-controller"
  display_name = "ws-cli-controller"
}

resource "google_service_account" "gateway" {
  project      = var.project_id
  account_id   = "ws-cli-gateway"
  display_name = "ws-cli-gateway"
}

resource "google_project_iam_member" "controller_k8s_job_creator" {
  project = var.project_id
  role    = "roles/container.developer" # More granular role is better
  member  = "serviceAccount:${google_service_account.controller.email}"
}

resource "google_project_iam_member" "controller_firebase_auth" {
  project = var.project_id
  role    = "roles/firebaseauth.viewer"
  member  = "serviceAccount:${google_service_account.controller.email}"
}

resource "google_service_account_iam_binding" "controller_workload_identity" {
  service_account_id = google_service_account.controller.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[ws-cli/ws-cli-controller]",
  ]
}

resource "google_service_account_iam_binding" "gateway_workload_identity" {
  service_account_id = google_service_account.gateway.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[ws-cli/ws-cli-gateway]",
  ]
}

# resource "helm_release" "cliscale" {
#   name              = "cliscale"
#   chart             = "../cliscale-chart"
#   namespace         = "ws-cli"
#   create_namespace  = true

#   values = [
#     yamlencode({
#       controller = {
#         image = {
#           repository = "${google_artifact_registry_repository.main.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.main.repository_id}/controller"
#           tag        = var.controller_image_tag
#         }
#         runnerImage = "${google_artifact_registry_repository.main.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.main.repository_id}/runner:${var.runner_image_tag}"
#         serviceAccount = {
#           gcpServiceAccount = google_service_account.controller.email
#         }
#       }
#       gateway = {
#         image = {
#           repository = "${google_artifact_registry_repository.main.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.main.repository_id}/gateway"
#           tag        = var.gateway_image_tag
#         }
#         serviceAccount = {
#           gcpServiceAccount = google_service_account.gateway.email
#         }
#       }
#       cloudsql = {
#         instanceConnectionName = google_sql_database_instance.main.connection_name
#       }
#       domain   = var.domain
#       wsDomain = var.ws_domain
#     })
#   ]

#   depends_on = [google_container_cluster.primary]
# }
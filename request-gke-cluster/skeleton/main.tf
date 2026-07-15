terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = "${{ values.region }}"
}

variable "project_id" {
  type        = string
  description = "The GCP Project ID to deploy the GKE Cluster in"
}

# VPC Network for GKE (Production Best Practice)
resource "google_compute_network" "gke_vpc" {
  name                    = "${{ values.serviceName }}-gke-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "gke_subnet" {
  name          = "${{ values.serviceName }}-gke-subnet"
  ip_cidr_range = "10.0.0.0/16"
  region        = "${{ values.region }}"
  network       = google_compute_network.gke_vpc.id

  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = "10.2.0.0/20"
  }
}

# GKE Cluster Definition (Control Plane only)
resource "google_container_cluster" "primary" {
  name     = "${{ values.serviceName }}"
  location = "${{ values.region }}"

  # We create a custom VPC and Subnet instead of using default
  network    = google_compute_network.gke_vpc.name
  subnetwork = google_compute_subnetwork.gke_subnet.name

  # During creation, we must create at least one node pool,
  # but best practice is to delete the default node pool and build a separate one.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Disable deletion protection for dev/testing ease
  deletion_protection = false

  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }
}

# Managed GKE Node Pool
resource "google_container_node_pool" "primary_nodes" {
  name       = "${{ values.serviceName }}-node-pool"
  location   = "${{ values.region }}"
  cluster    = google_container_cluster.primary.name
  node_count = ${{ values.nodeCount }}

  node_config {
    preemptible  = true
    machine_type = "${{ values.machineType }}"

    # Metadata labels for tracking
    labels = {
      environment = "${{ values.environment }}"
      requester   = "${{ values.requester }}"
    }

    # IAM permissions for GKE nodes (GCR access, logging, monitoring)
    oauth_scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/servicecontrol",
    ]
  }

  # Enable autoscaling to show production behavior
  autoscaling {
    min_node_count = 1
    max_node_count = 5
  }
}

output "cluster_name" {
  value       = google_container_cluster.primary.name
  description = "The name of the GKE cluster"
}

output "kubernetes_endpoint" {
  value       = google_container_cluster.primary.endpoint
  description = "The Kubernetes Control Plane API server endpoint"
}

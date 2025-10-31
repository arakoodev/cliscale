variable "project_id" {
  description = "The GCP project ID to deploy resources into."
  type        = string
}

variable "region" {
  description = "The GCP region to deploy resources into."
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "The name of the GKE cluster."
  type        = string
}

variable "sql_instace_name" {
  description = "The name of the Cloud SQL instance."
  type          = string
}

variable "sql_database_version" {
  description = "The version of the Cloud SQL database."
  type        = string
  default     = "POSTGRES_15"
}

variable "sql_machine_type" {
  description = "The machine type of the Cloud SQL database"
  type        = string
  default     = "db-g1-small"
}

variable "disk_autoresize" {
  description = "Configuration to increase storage size."
  type        = bool
  default     = true
}

variable "disk_autoresize_limit" {
  description = "The maximum size to which storage can be auto increased."
  type        = number
  default     = 0
}

variable "disk_size" {
  description = "The disk size (in GB) for the Cloud SQL instance."
  type        = number
  default     = 10
}

variable "disk_type" {
  description = "The disk type for the Cloud SQL instance."
  type        = string
  default     = "PD_SSD"
}

variable "db_user" {
  description = "The username for the Cloud SQL database."
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "The password for the Cloud SQL database."
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "The name of the Cloud SQL database."
  type        = string
  default     = "wscli"
}

variable "controller_image_tag" {
  description = "The image tag for the controller service."
  type        = string
  default     = "latest"
}

variable "gateway_image_tag" {
  description = "The image tag for the gateway service."
  type        = string
  default     = "latest"
}

variable "runner_image_tag" {
  description = "The image tag for the runner service."
  type        = string
  default     = "latest"
}

variable "domain" {
  description = "The domain for the controller ingress."
  type        = string
}

variable "ws_domain" {
  description = "The domain for the gateway ingress."
  type        = string
}
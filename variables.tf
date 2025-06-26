variable "aws_region" {
  description = "Región de AWS."
  type        = string
  default     = "eu-central-1"
}
variable "db_username" {
  description = "Usuario de la base de datos."
  type        = string
  sensitive   = true
}
variable "db_password" {
  description = "Contraseña de la base de datos."
  type        = string
  sensitive   = true
}
variable "gcp_project_id" {
  description = "Proyecto de GCP donde se desplegará la aplicación."
  type        = string
  sensitive   = true
}
variable "gcp_region" {
  description = "Región de GCP donde se desplegará la aplicación."
  type        = string
  sensitive   = true
}
variable "db_name" {
  description = "Nombre de la base de datos en RDS"
  type        = string
}

variable "datastream_user" {
  description = "Usuario que usará DataStream para acceder a RDS"
  type        = string
}

variable "datastream_password" {
  description = "Contraseña para el usuario de DataStream"
  type        = string
  sensitive   = true
}

variable "replication_slot" {
  description = "Nombre del replication slot lógico en PostgreSQL"
  type        = string
}

variable "publication" {
  description = "Nombre de la publicación para replicación lógica"
  type        = string
}
variable "datastream_region" {
  description = "Región de GCP donde se desplegará DataStream."
  type        = string
  sensitive   = true
}

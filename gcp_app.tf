# main.tf completo para desplegar app Flask en Cloud Run (GCP) con Terraform

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# ============================
# 1. Activar APIs necesarias
# ============================
resource "google_project_service" "run" {
  service             = "run.googleapis.com"
  project             = var.gcp_project_id
  disable_on_destroy = false
}

resource "google_project_service" "artifact" {
  service             = "artifactregistry.googleapis.com"
  project             = var.gcp_project_id
  disable_on_destroy = false
}

resource "google_project_service" "iam" {
  service             = "iam.googleapis.com"
  project             = var.gcp_project_id
  disable_on_destroy = false
}

# ==================================
# 2. Crear repositorio Artifact Registry
# ==================================
resource "google_artifact_registry_repository" "flask_repo" {
  location      = var.gcp_region
  repository_id = "flask-app-repo"
  description   = "Repo para imagen Docker de app Flask"
  format        = "DOCKER"
  depends_on = [
    google_project_service.artifact
  ]
}

# ==================================
# 3. Crear servicio en Cloud Run
# ==================================
resource "null_resource" "build_flask_app" {
  provisioner "local-exec" {
    command = <<EOT
      docker buildx inspect gcp-builder >/dev/null 2>&1 || docker buildx create --name gcp-builder --driver docker-container --use
      gcloud auth configure-docker ${var.gcp_region}-docker.pkg.dev --quiet
      docker buildx build \
        --builder gcp-builder \
        --platform linux/amd64 \
        --push \
        -t ${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/flask-app-repo/flask-app:v13 \
        .
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    always_rebuild = timestamp()
  }


  depends_on = [
    google_artifact_registry_repository.flask_repo,
    google_project_service.artifact
  ]
}


resource "google_cloud_run_service" "flask_service" {
  name     = "flask-app"
  location = var.gcp_region

  template {
    spec {
      containers {
        image = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/flask-app-repo/flask-app:v13"
        ports {
          container_port = 5001
        }
        env {
          name  = "API_BASE_URL"
          value = aws_api_gateway_stage.api_stage.invoke_url
        }
        env {
          name  = "PG_HOST"
          value = aws_db_instance.postgres.address
        }
        env {
          name  = "PG_DB"
          value = aws_db_instance.postgres.db_name
        }
        env {
          name  = "PG_USER"
          value = aws_db_instance.postgres.username
        }
        env {
          name  = "PG_PASSWORD"
          value = var.db_password
        }
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [
    google_project_service.run,
    google_artifact_registry_repository.flask_repo,
    null_resource.build_flask_app
  ]
}

# ==================================
# 4. Hacer público el servicio Cloud Run
# ==================================
resource "google_cloud_run_service_iam_member" "public_access" {
  location = google_cloud_run_service.flask_service.location
  service  = google_cloud_run_service.flask_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
  depends_on = [
    google_project_service.iam
  ]
}

# ==================================
# 5. Output URL
# ==================================
output "cloud_run_url" {
  value = google_cloud_run_service.flask_service.status[0].url
}

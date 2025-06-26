## APIS
resource "google_project_service" "enable_secretmanager" {
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "enable_datastream" {
  service            = "datastream.googleapis.com"
  disable_on_destroy = false
}

## SECRETS
resource "google_secret_manager_secret" "rds_password" {
  secret_id = "datastream-rds-password"

  replication {
    auto {}
  }

  depends_on = [google_project_service.enable_secretmanager]
}

resource "google_secret_manager_secret_version" "rds_password_version" {
  secret      = google_secret_manager_secret.rds_password.id
  secret_data = var.datastream_password
}

## PARAMETER GROUP
resource "aws_db_parameter_group" "logical_replication" {
  name        = "rds-logical-replication"
  family      = "postgres15"
  description = "Parameter group with wal_level=logical"
  
  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "max_replication_slots"
    value        = "10"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "max_wal_senders"
    value        = "10"
    apply_method = "pending-reboot"
  }
}


## CONNECTION PROFILES
resource "google_datastream_connection_profile" "rds_source" {
  connection_profile_id = "rds-source-connection"
  location               = var.gcp_region
  display_name           = "AWS RDS Source"

  postgresql_profile {
    hostname = aws_db_instance.postgres.address
    port     = 5432
    username = var.datastream_user
    password = var.datastream_password
    database = var.db_name
  }
  depends_on = [google_project_service.enable_datastream]
}

resource "google_datastream_connection_profile" "bq_destination" {
  connection_profile_id = "bigquery-destination-connection"
  location               = var.gcp_region
  display_name           = "BigQuery Destination"

  bigquery_profile {}

  depends_on = [google_project_service.enable_datastream]
}

## DATASTREAM STREAM
resource "google_datastream_stream" "replication" {
  stream_id     = "rds-to-bigquery"
  display_name  = "Replicación RDS a BigQuery"
  location      = var.gcp_region
  desired_state = "RUNNING"

  source_config {
    source_connection_profile = google_datastream_connection_profile.rds_source.id

    postgresql_source_config {
      replication_slot = var.replication_slot
      publication      = var.publication

      include_objects {
        postgresql_schemas {
          schema = "public"

          postgresql_tables {
            table = "test_datastream"
          }

          postgresql_tables {
            table = "productos"
          }
        }
      }
    }
  }

  destination_config {
    destination_connection_profile = google_datastream_connection_profile.bq_destination.id

    bigquery_destination_config {
      data_freshness = "900s"

      source_hierarchy_datasets {
        dataset_template {
          location = var.gcp_region
        }
      }
    }
  }

  backfill_all {}

  depends_on = [
    google_datastream_connection_profile.rds_source,
    google_datastream_connection_profile.bq_destination
  ]
}

## POSTGRES CONFIGURATION
resource "null_resource" "configure_rds_for_datastream" {
  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = <<-EOT
      export PGPASSWORD="${var.db_password}"
      psql -h ${aws_db_instance.postgres.address} -U ${var.db_username} -d ${var.db_name} -c "CREATE PUBLICATION ${var.publication} FOR ALL TABLES;"
      psql -h ${aws_db_instance.postgres.address} -U ${var.db_username} -d ${var.db_name} -c "SELECT PG_CREATE_LOGICAL_REPLICATION_SLOT('${var.replication_slot}', 'pgoutput');"
      psql -h ${aws_db_instance.postgres.address} -U ${var.db_username} -d ${var.db_name} -c "CREATE USER ${var.datastream_user} WITH ENCRYPTED PASSWORD '${var.datastream_password}';"
      psql -h ${aws_db_instance.postgres.address} -U ${var.db_username} -d ${var.db_name} -c "GRANT rds_replication TO ${var.datastream_user};"
      psql -h ${aws_db_instance.postgres.address} -U ${var.db_username} -d ${var.db_name} -c "GRANT USAGE ON SCHEMA public TO ${var.datastream_user};"
      psql -h ${aws_db_instance.postgres.address} -U ${var.db_username} -d ${var.db_name} -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${var.datastream_user};"
      psql -h ${aws_db_instance.postgres.address} -U ${var.db_username} -d ${var.db_name} -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO ${var.datastream_user};"
    EOT
  }
}

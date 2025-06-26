output "api_endpoint" {
  description = "URL de la API Gateway (incluyendo la etapa)."
  # CORREGIDO: Apunta al 'invoke_url' del nuevo recurso 'aws_api_gateway_stage'
  value       = aws_api_gateway_stage.api_stage.invoke_url
}

output "rds_endpoint" {
  description = "Endpoint público de la base de datos RDS."
  value       = aws_db_instance.postgres.endpoint
}
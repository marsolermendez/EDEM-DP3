# =================================================================
# 1. PROVEEDOR
# =================================================================
provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# =================================================================
# 2. RED (PÚBLICA)
# =================================================================
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "tienda-vpc-publica" }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags                    = { Name = "public-subnet-a" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
  tags                    = { Name = "public-subnet-b" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "tienda-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# =================================================================
# 3. SEGURIDAD (RDS PÚBLICO)
# =================================================================
resource "aws_security_group" "rds_sg" {
  name        = "tienda-rds-sg-public"
  description = "Allow all traffic to RDS for development"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# =================================================================
# 4. BASE DE DATOS (PÚBLICA)
# =================================================================
resource "aws_db_subnet_group" "default" {
  name       = "tienda-db-subnet-group-public"
  subnet_ids = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

resource "aws_db_instance" "postgres" {
  identifier             = "tienda-db-public"
  allocated_storage      = 10
  engine                 = "postgres"
  engine_version         = "15.7"
  instance_class         = "db.t3.micro"
  db_name                = "tiendadb"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
  publicly_accessible    = true
  parameter_group_name   = aws_db_parameter_group.logical_replication.name
  apply_immediately = true

  depends_on = [ aws_db_parameter_group.logical_replication ]
}

# =================================================================
# 5. INICIALIZACIÓN DE ESQUEMA RDS
# =================================================================
resource "null_resource" "init_schema" {
  depends_on = [aws_db_instance.postgres]

   triggers = {
    always_run = timestamp()
  }
  
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    # Usamos .address y .port por separado para mayor claridad
    command     = "sleep 30 && export PGPASSWORD='${var.db_password}' && psql -h ${aws_db_instance.postgres.address} -p ${aws_db_instance.postgres.port} -U ${var.db_username} -d ${aws_db_instance.postgres.db_name} -f '${path.module}/schemas/init.sql'"
  }
}

# =================================================================
# 6. IAM ROLE (COMPARTIDO PARA TODAS LAS LAMBDAS)
# =================================================================
resource "aws_iam_role" "lambda_exec" {
  name               = "tienda_lambda_exec_role_docker"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "null_resource" "ecr_login" {
  # Se ejecuta siempre para asegurar que el token de 12 horas esté fresco
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  }
}

# =================================================================
# 7. LAMBDA: GET_PRODUCTS
# =================================================================
resource "aws_ecr_repository" "get_products" {
  name         = "get-products"
  force_delete = true # Permite borrar el repo aunque contenga imágenes
}

resource "null_resource" "build_get_products" {
  provisioner "local-exec" {
    command = <<EOT
      docker buildx build \
        --builder lambda-builder \
        --platform linux/amd64 \
        --push \
        --provenance=false \
        -t ${aws_ecr_repository.get_products.repository_url}:latest \
        ${path.module}/Lambdas/get_products
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    source_hash = sha1(filebase64sha256("${path.module}/Lambdas/get_products/Dockerfile"))
  }

  depends_on = [
    aws_ecr_repository.get_products,
    null_resource.ecr_login
  ]
}

resource "aws_lambda_function" "get_products" {
  function_name = "get_products_final"
  role          = aws_iam_role.lambda_exec.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.get_products.repository_url}:latest"
  timeout       = 30
  
  environment {
    variables = {
      DB_HOST     = aws_db_instance.postgres.address
      DB_PORT     = aws_db_instance.postgres.port
      DB_NAME     = aws_db_instance.postgres.db_name
      DB_USER     = var.db_username
      DB_PASSWORD = var.db_password
    }
  }

  depends_on = [null_resource.build_get_products]
}

# =================================================================
# 8. LAMBDA: ADD_PRODUCT
# =================================================================
resource "aws_ecr_repository" "add_product" {
  name         = "add-product"
  force_delete = true
}

resource "null_resource" "build_add_product" {
  provisioner "local-exec" {
    command = <<EOT
      docker buildx build \
        --builder lambda-builder \
        --platform linux/amd64 \
        --push \
        --provenance=false \
        -t ${aws_ecr_repository.add_product.repository_url}:latest \
        ${path.module}/Lambdas/add_product
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    source_hash = sha1(filebase64sha256("${path.module}/Lambdas/add_product/Dockerfile"))
  }

  depends_on = [
    aws_ecr_repository.add_product,
    null_resource.ecr_login
  ]
}

resource "aws_lambda_function" "add_product" {
  function_name = "add_product_final"
  role          = aws_iam_role.lambda_exec.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.add_product.repository_url}:latest"
  timeout       = 30

  environment {
    variables = {
      DB_HOST     = aws_db_instance.postgres.address
      DB_PORT     = aws_db_instance.postgres.port
      DB_NAME     = aws_db_instance.postgres.db_name
      DB_USER     = var.db_username
      DB_PASSWORD = var.db_password
    }
  }

  depends_on = [null_resource.build_add_product]
}

# =================================================================
# 9. LAMBDA: GET_ITEM
# =================================================================
resource "aws_ecr_repository" "get_item" {
  name         = "get-item"
  force_delete = true
}

resource "null_resource" "build_get_item" {
  provisioner "local-exec" {
    command = <<EOT
      docker buildx build \
        --builder lambda-builder \
        --platform linux/amd64 \
        --push \
        --provenance=false \
        -t ${aws_ecr_repository.get_item.repository_url}:latest \
        ${path.module}/Lambdas/get_item
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    source_hash = sha1(filebase64sha256("${path.module}/Lambdas/get_item/Dockerfile"))
  }

  depends_on = [
    aws_ecr_repository.get_item,
    null_resource.ecr_login
  ]
}

resource "aws_lambda_function" "get_item" {
  function_name = "get_item_final"
  role          = aws_iam_role.lambda_exec.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.get_item.repository_url}:latest"
  timeout       = 30

  environment {
    variables = {
      DB_HOST     = aws_db_instance.postgres.address
      DB_PORT     = aws_db_instance.postgres.port
      DB_NAME     = aws_db_instance.postgres.db_name
      DB_USER     = var.db_username
      DB_PASSWORD = var.db_password
    }
  }

  depends_on = [null_resource.build_get_item]
}

# =================================================================
# 10. API GATEWAY (USANDO API REST v1)
# =================================================================
resource "aws_api_gateway_rest_api" "api" {
  name        = "tienda-api-docker-final"
  description = "API para la tienda online"
}

# --- Recurso y Método para GET /products ---
resource "aws_api_gateway_resource" "get_products_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "products"
}
resource "aws_api_gateway_method" "get_products_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.get_products_resource.id
  http_method   = "GET"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "get_products_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.get_products_resource.id
  http_method             = aws_api_gateway_method.get_products_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_products.invoke_arn
}

# --- Método para POST /products ---
resource "aws_api_gateway_method" "add_product_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.get_products_resource.id
  http_method   = "POST"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "add_product_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.get_products_resource.id
  http_method             = aws_api_gateway_method.add_product_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.add_product.invoke_arn
}

# --- Recurso y Método para POST /comprar ---
resource "aws_api_gateway_resource" "get_item_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "comprar"
}
resource "aws_api_gateway_method" "get_item_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.get_item_resource.id
  http_method   = "POST"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "get_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.get_item_resource.id
  http_method             = aws_api_gateway_method.get_item_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_item.invoke_arn
}

# --- Despliegue y Etapa de la API ---
resource "aws_api_gateway_deployment" "api" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.api.body))
  }
  
  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.get_products_integration,
    aws_api_gateway_integration.add_product_integration,
    aws_api_gateway_integration.get_item_integration,
    aws_api_gateway_method_response.get_products_200,
    aws_api_gateway_integration_response.get_products_200,
    aws_api_gateway_method_response.add_product_200,
    aws_api_gateway_integration_response.add_product_200,
    aws_api_gateway_method_response.get_item_200,
    aws_api_gateway_integration_response.get_item_200
  ]
}

resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.api.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "v1"
}


# --- Permisos de Invocación ---
resource "aws_lambda_permission" "allow_api_get_products" {
  statement_id  = "AllowAPIGatewayInvokeGetProducts"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_products.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}
resource "aws_lambda_permission" "allow_api_add_product" {
  statement_id  = "AllowAPIGatewayInvokeAddProduct"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_product.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}
resource "aws_lambda_permission" "allow_api_get_item" {
  statement_id  = "AllowAPIGatewayInvokeGetItem"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# ----- CORS -----

resource "aws_api_gateway_method_response" "get_products_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.get_products_resource.id
  http_method = aws_api_gateway_method.get_products_method.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
  depends_on = [aws_api_gateway_integration.get_products_integration]
}
resource "aws_api_gateway_integration_response" "get_products_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.get_products_resource.id
  http_method = aws_api_gateway_method.get_products_method.http_method
  status_code = aws_api_gateway_method_response.get_products_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
  depends_on = [aws_api_gateway_integration.get_products_integration]
}

resource "aws_api_gateway_method_response" "add_product_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.get_products_resource.id
  http_method = aws_api_gateway_method.add_product_method.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
  depends_on = [aws_api_gateway_integration.add_product_integration]
}

resource "aws_api_gateway_integration_response" "add_product_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.get_products_resource.id
  http_method = aws_api_gateway_method.add_product_method.http_method
  status_code = aws_api_gateway_method_response.add_product_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
  depends_on = [aws_api_gateway_integration.add_product_integration]
}

resource "aws_api_gateway_method_response" "get_item_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.get_item_resource.id
  http_method = aws_api_gateway_method.get_item_method.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
  depends_on = [aws_api_gateway_integration.get_item_integration]
}

resource "aws_api_gateway_integration_response" "get_item_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.get_item_resource.id
  http_method = aws_api_gateway_method.get_item_method.http_method
  status_code = aws_api_gateway_method_response.get_item_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
  depends_on = [aws_api_gateway_integration.get_item_integration]
}

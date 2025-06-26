
# Data Project 3

Este proyecto implementa una aplicación web de gestión de productos, con frontend en HTML+Tailwind, backend en Flask y base de datos PostgreSQL. Está completamente desplegado en Google Cloud Run usando infraestructura como código con Terraform, y la base de datos está alojada en AWS RDS.

Además:

- Se utilizan funciones **AWS Lambda** para exponer la base de datos como puente temporal, facilitando el acceso desde Cloud Run.
- La infraestructura está en **red pública**, dado que es un **entorno de desarrollo**.
- Se incorpora **Google DataStream** para replicar los datos de RDS en tiempo (casi) real hacia **BigQuery**, donde actúa como capa OLAP para análisis.


---

## 🧱 Tecnologías utilizadas

- **Frontend**: HTML, TailwindCSS y JavaScript puro  
- **Backend**: Python (Flask)  
- **Base de datos**: PostgreSQL (AWS RDS)  
- **OLAP**: Google BigQuery  
- **Replicación**: Google DataStream  
- **Infraestructura**: Terraform  
- **Despliegue**: Docker + Cloud Run  
- **Integración temporal**: AWS Lambda  

---

## 🚀 Funcionalidades

- Ver lista de productos con stock  
- Añadir nuevos productos  
- Comprar productos (reduce el stock)  
- Datos replicados en BigQuery para análisis

---

## 🛠️ Instrucciones de uso

### 1. Configura variables

Crea un archivo `terraform.tfvars` con tus valores de:

- Credenciales de GCP y AWS  
- Nombres de instancias, región, VPC, etc.  
- Datos de conexión a la base de datos  

### 2. Inicializa Terraform

```bash
terraform init
```

### 3. Aplica la infraestructura

```bash
terraform apply
```
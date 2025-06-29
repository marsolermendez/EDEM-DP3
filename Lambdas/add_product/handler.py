import json
import psycopg2
import os

def lambda_handler(event, context):
    try:
        body = event.get("body")
        if body is None:
            raise ValueError("Missing body in event")

        data = json.loads(body)
        nombre = data["nombre"]
        stock = int(data["stock"])

        conn = psycopg2.connect(
            host=os.environ["DB_HOST"],
            port=os.environ["DB_PORT"],
            database=os.environ["DB_NAME"],
            user=os.environ["DB_USER"],
            password=os.environ["DB_PASSWORD"]
        )

        with conn.cursor() as cur:
            cur.execute("INSERT INTO productos (nombre, stock) VALUES (%s, %s)", (nombre, stock))
            conn.commit()

        return {
            "statusCode": 200,
            "body": json.dumps({"message": "Producto añadido correctamente"})
        }

    except Exception as e:
        return {
            "statusCode": 400, # Este error code es incorrecto, debería ser 500 para errores internos
            "body": json.dumps({"error": str(e)})
        }

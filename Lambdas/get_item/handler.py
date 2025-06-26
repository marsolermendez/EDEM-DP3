import json
import psycopg2
import os

def lambda_handler(event, context):
    try:
        body = event.get("body")
        if body is None:
            raise ValueError("Missing body in event")

        data = json.loads(body)
        producto_id = int(data["producto_id"])

        conn = psycopg2.connect(
            host=os.environ["DB_HOST"],
            port=os.environ["DB_PORT"],
            database=os.environ["DB_NAME"],
            user=os.environ["DB_USER"],
            password=os.environ["DB_PASSWORD"]
        )

        with conn.cursor() as cur:
            cur.execute("SELECT stock FROM productos WHERE id = %s", (producto_id,))
            row = cur.fetchone()
            if not row:
                raise ValueError("Producto no encontrado")

            stock_actual = row[0]
            if stock_actual <= 0:
                raise ValueError("Stock insuficiente")

            cur.execute("UPDATE productos SET stock = stock - 1 WHERE id = %s", (producto_id,))
            conn.commit()

        return {
            "statusCode": 200,
            "body": json.dumps({"message": "Compra realizada correctamente"})
        }

    except Exception as e:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": str(e)})
        }
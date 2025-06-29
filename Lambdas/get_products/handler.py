import json
import os
import psycopg2
import psycopg2.extras # Para convertir el resultado en un diccionario fácilmente

def handler(event, context):
    print("🔍 Entrando al handler de get_products...")
    conn = None
    try:
        conn = psycopg2.connect(
            host=os.environ['DB_HOST'], dbname=os.environ['DB_NAME'],
            user=os.environ['DB_USER'], password=os.environ['DB_PASSWORD'],
            port=os.environ.get('DB_PORT', 5432)
        )
        print("✅ Conexión a la BBDD exitosa")
        
        # Usamos un cursor que devuelve diccionarios para facilitar la conversión a JSON
        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        
        cursor.execute("SELECT id, nombre, stock FROM productos ORDER BY id;")
        result = cursor.fetchall()
        print("📦 Datos obtenidos:", result)

        return {
            "statusCode": 200,
            "headers": { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
            "body": json.dumps(result, default=str)
        }
    except Exception as e:
        print(f"❌ Error en get_products: {e}")
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}
    finally: # Esta parte debería estar en todas las lambdas
        if conn:
            conn.close()
            print("🔌 Conexión a la BBDD cerrada.")

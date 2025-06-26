import os
import requests
from flask import Flask, render_template, request, jsonify

app = Flask(__name__, template_folder='templates')

API_BASE_URL = os.getenv("API_BASE_URL")
print("🌍 API_BASE_URL:", API_BASE_URL)

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/api/products", methods=["GET"])
def get_products():
    try:
        response = requests.get(f"{API_BASE_URL}/products")
        response.raise_for_status()
        return jsonify(response.json())
    except Exception as e:
        print("💥 Error al obtener productos:", e)
        return jsonify({"error": "Respuesta inesperada de productos"}), 500

@app.route("/api/products", methods=["POST"])
def add_product():
    try:
        data = request.get_json()
        print("📦 Datos recibidos para POST /products:", data)
        response = requests.post(f"{API_BASE_URL}/products", json=data)
        response.raise_for_status()
        return jsonify(response.json())
    except Exception as e:
        print("💥 Error al añadir producto:", e)
        return jsonify({"error": "No se pudo añadir el producto"}), 500

@app.route("/api/comprar", methods=["POST"])
def comprar():
    try:
        data = request.get_json()
        print("🛒 Datos recibidos para POST /comprar:", data)
        response = requests.post(f"{API_BASE_URL}/comprar", json=data)
        response.raise_for_status()
        return jsonify(response.json())
    except Exception as e:
        print("💥 Error al comprar:", e)
        return jsonify({"error": "No se pudo completar la compra"}), 500

@app.route("/api/ping")
def ping():
    return "pong"

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))

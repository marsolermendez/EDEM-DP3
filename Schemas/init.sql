-- Elimina la tabla si ya existe para una inicialización limpia
DROP TABLE IF EXISTS productos;

-- Crea la tabla de productos
CREATE TABLE productos (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(255) NOT NULL,
    stock INTEGER DEFAULT 0
);

-- Inserta algunos datos de ejemplo (opcional)
INSERT INTO productos (nombre, stock) VALUES
('Portátil Pro', 15),
('Teclado Mecánico', 50),
('Monitor 4K', 25);
CREATE TABLE IF NOT EXISTS customers (
  id CHAR(36) PRIMARY KEY, name VARCHAR(120) NOT NULL, email VARCHAR(255) NOT NULL UNIQUE,
  phone VARCHAR(40) NOT NULL, created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
);
CREATE TABLE IF NOT EXISTS addresses (
  id CHAR(36) PRIMARY KEY, customer_id CHAR(36) NOT NULL, label VARCHAR(80) NOT NULL,
  line1 VARCHAR(255) NOT NULL, city VARCHAR(80) NOT NULL, region VARCHAR(80) NOT NULL,
  is_default BOOLEAN NOT NULL DEFAULT FALSE, INDEX ix_addresses_customer (customer_id),
  CONSTRAINT fk_addresses_customer FOREIGN KEY (customer_id) REFERENCES customers(id)
);
CREATE TABLE IF NOT EXISTS order_history (
  order_id CHAR(36) PRIMARY KEY, customer_id CHAR(36) NOT NULL, restaurant_id CHAR(36) NOT NULL,
  total DECIMAL(10,2) NOT NULL, status VARCHAR(32) NOT NULL, placed_at TIMESTAMP(6) NOT NULL,
  updated_at TIMESTAMP(6) NOT NULL, INDEX ix_history_customer_placed (customer_id, placed_at)
);
CREATE TABLE IF NOT EXISTS processed_events (event_id CHAR(36) PRIMARY KEY, processed_at TIMESTAMP(6) NOT NULL);

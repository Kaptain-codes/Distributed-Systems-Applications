CREATE TABLE IF NOT EXISTS restaurants (
  id CHAR(36) PRIMARY KEY, name VARCHAR(120) NOT NULL, address VARCHAR(255) NOT NULL,
  contact VARCHAR(120) NOT NULL, is_active BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE TABLE IF NOT EXISTS restaurant_hours (
  restaurant_id CHAR(36) NOT NULL, day_of_week TINYINT NOT NULL, opens_at TIME NOT NULL,
  closes_at TIME NOT NULL, PRIMARY KEY (restaurant_id, day_of_week),
  CONSTRAINT fk_hours_restaurant FOREIGN KEY (restaurant_id) REFERENCES restaurants(id)
);
CREATE TABLE IF NOT EXISTS menu_items (
  id CHAR(36) PRIMARY KEY, restaurant_id CHAR(36) NOT NULL, name VARCHAR(120) NOT NULL,
  price DECIMAL(10,2) NOT NULL, is_available BOOLEAN NOT NULL DEFAULT TRUE, stock_qty INT NOT NULL DEFAULT 0,
  CONSTRAINT ck_menu_stock CHECK (stock_qty >= 0), INDEX ix_menu_restaurant (restaurant_id)
);
CREATE TABLE IF NOT EXISTS kitchen_orders (
  order_id CHAR(36) PRIMARY KEY, restaurant_id CHAR(36) NOT NULL, status VARCHAR(32) NOT NULL,
  items_json JSON NOT NULL, received_at TIMESTAMP(6) NOT NULL, decided_at TIMESTAMP(6) NULL,
  payment_confirmed_at TIMESTAMP(6) NULL, reject_reason VARCHAR(64) NULL,
  INDEX ix_kitchen_queue (restaurant_id, status)
);
CREATE TABLE IF NOT EXISTS processed_events (event_id CHAR(36) PRIMARY KEY, processed_at TIMESTAMP(6) NOT NULL);

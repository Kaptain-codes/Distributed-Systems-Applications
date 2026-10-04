-- Runs once when the customer-db volume is empty.
-- MYSQL_DATABASE already created the `customer` database.
USE customer;

CREATE TABLE IF NOT EXISTS customers (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    phone VARCHAR(64),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_customers_email (email)
);

INSERT IGNORE INTO customers (id, name, email, phone) VALUES
    ('11111111-1111-1111-1111-111111111111', 'Test User',    'test@example.com',    '+264811234567'),
    ('22222222-2222-2222-2222-222222222222', 'Alice Nakale', 'alice@example.com',   '+264812345678'),
    ('33333333-3333-3333-3333-333333333333', 'Bob Shikongo', 'bob@example.com',     '+264813456789');
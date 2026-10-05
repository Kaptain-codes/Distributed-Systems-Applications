IF DB_ID('delivery') IS NULL CREATE DATABASE delivery;
GO
USE delivery;
GO
IF OBJECT_ID('dbo.drivers', 'U') IS NULL
CREATE TABLE drivers (id UNIQUEIDENTIFIER PRIMARY KEY, name NVARCHAR(120) NOT NULL, phone NVARCHAR(40) NOT NULL,
  status VARCHAR(16) NOT NULL, last_assigned_at DATETIME2 NULL);
IF OBJECT_ID('dbo.deliveries', 'U') IS NULL
CREATE TABLE deliveries (id UNIQUEIDENTIFIER PRIMARY KEY, order_id UNIQUEIDENTIFIER NOT NULL UNIQUE,
  restaurant_id UNIQUEIDENTIFIER NOT NULL, driver_id UNIQUEIDENTIFIER NULL, pickup_address NVARCHAR(255) NOT NULL,
  dropoff_address NVARCHAR(255) NOT NULL, status VARCHAR(16) NOT NULL, attempts INT NOT NULL DEFAULT 0,
  assigned_at DATETIME2 NULL, completed_at DATETIME2 NULL, failure_reason NVARCHAR(255) NULL);
IF OBJECT_ID('dbo.processed_events', 'U') IS NULL
CREATE TABLE processed_events (event_id UNIQUEIDENTIFIER PRIMARY KEY, processed_at DATETIME2 NOT NULL);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_drivers_status_last_assigned_at'
  AND object_id = OBJECT_ID('dbo.drivers'))
CREATE INDEX ix_drivers_status_last_assigned_at ON drivers(status, last_assigned_at);

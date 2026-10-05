INSERT INTO restaurants (id,name,address,contact,is_active) VALUES
('00000000-0000-4000-8000-000000000002','Demo Kitchen','10 Sam Nujoma Drive','demo-kitchen@example.test',TRUE)
ON DUPLICATE KEY UPDATE is_active=TRUE;
INSERT INTO menu_items (id,restaurant_id,name,price,is_available,stock_qty) VALUES
('00000000-0000-4000-8000-000000000021','00000000-0000-4000-8000-000000000002','Demo Bowl',25.00,TRUE,100)
ON DUPLICATE KEY UPDATE stock_qty=100,is_available=TRUE;

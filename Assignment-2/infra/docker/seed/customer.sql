INSERT INTO customers (id,name,email,phone) VALUES
('00000000-0000-4000-8000-000000000001','Demo Customer','demo@example.test','+264810000001')
ON DUPLICATE KEY UPDATE name=VALUES(name);
INSERT INTO addresses (id,customer_id,label,line1,city,region,is_default) VALUES
('00000000-0000-4000-8000-000000000011','00000000-0000-4000-8000-000000000001','Home','1 Independence Avenue','Windhoek','Khomas',TRUE)
ON DUPLICATE KEY UPDATE line1=VALUES(line1);

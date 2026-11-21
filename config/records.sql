-- Records database (stands in for the Banner database). Sample data only.
CREATE ROLE banner LOGIN PASSWORD 'Campus-Lab-2026!';
CREATE DATABASE records OWNER banner;
\connect records
CREATE TABLE students (
    id       serial PRIMARY KEY,
    g_number text NOT NULL,
    name     text NOT NULL,
    program  text NOT NULL,
    balance  numeric(8,2) NOT NULL
);
INSERT INTO students (g_number, name, program, balance) VALUES
    ('G00000001', 'Sample Student A', 'BS Information Technology', 1250.00),
    ('G00000002', 'Sample Student B', 'MS Cyber Security Engineering', 0.00),
    ('G00000003', 'Sample Student C', 'BS Computer Science', 640.50);
ALTER TABLE students OWNER TO banner;

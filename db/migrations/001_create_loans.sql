CREATE TABLE IF NOT EXISTS loans (
    id SERIAL PRIMARY KEY,
    borrower_name TEXT NOT NULL,
    loan_amount NUMERIC(14,2) NOT NULL,
    property_city TEXT,
    status TEXT NOT NULL DEFAULT 'PENDING',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO loans (
    borrower_name,
    loan_amount,
    property_city,
    status
)
VALUES
    ('Aarav Sharma', 4500000.00, 'Mumbai', 'APPROVED'),
    ('Priya Patel', 3200000.00, 'Pune', 'PENDING'),
    ('Rahul Mehta', 5800000.00, 'Bengaluru', 'APPROVED'),
    ('Sneha Kulkarni', 2750000.00, 'Nagpur', 'PENDING'),
    ('Vikram Singh', 4100000.00, 'Delhi', 'REJECTED');
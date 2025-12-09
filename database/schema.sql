-- ============================================================
-- KITCHEN4U - DATABASE SCHEMA
-- PostgreSQL 17
-- ============================================================
-- Questo script crea tutte le tabelle necessarie per l'app Kitchen4u
-- che supporta: Vendita Spot, Abbonamenti (Subscription) e Wallet
-- ============================================================

-- Abilita estensioni utili
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 🧱 AREA 1: UTENTI, PROFILAZIONE E FINANCE (CRM & Wallet)
-- ============================================================

-- 1. USERS (Clienti)
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    stripe_customer_id VARCHAR(255),
    wallet_balance DECIMAL(10, 2) DEFAULT 0.00 NOT NULL,
    preferences JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_stripe_customer_id ON users(stripe_customer_id);

-- 2. USER_ADDRESSES (Indirizzi di Consegna)
CREATE TABLE user_addresses (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    street_address VARCHAR(255) NOT NULL,
    city VARCHAR(100) NOT NULL,
    postal_code VARCHAR(20) NOT NULL,
    province VARCHAR(50),
    notes TEXT,
    is_default BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_user_addresses_user_id ON user_addresses(user_id);

-- 3. WALLET_TRANSACTIONS (Estratto Conto Virtuale)
CREATE TYPE wallet_transaction_type AS ENUM ('DEPOSIT', 'ORDER_PAYMENT', 'REFUND', 'BONUS');

CREATE TABLE wallet_transactions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount DECIMAL(10, 2) NOT NULL,
    type wallet_transaction_type NOT NULL,
    reference_order_id INTEGER,
    description VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_wallet_transactions_user_id ON wallet_transactions(user_id);
CREATE INDEX idx_wallet_transactions_type ON wallet_transactions(type);

-- ============================================================
-- 🥦 AREA 2: MAGAZZINO E FOOD COST (Back-End Cucina)
-- ============================================================

-- 4. SUPPLIERS (Fornitori)
CREATE TABLE suppliers (
    id SERIAL PRIMARY KEY,
    company_name VARCHAR(255) NOT NULL,
    contact_email VARCHAR(255),
    contact_phone VARCHAR(20),
    address TEXT,
    lead_time_days INTEGER DEFAULT 1,
    notes TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 5. INGREDIENTS (Materie Prime)
CREATE TYPE unit_measure AS ENUM ('KG', 'L', 'PZ', 'GR', 'ML');

CREATE TABLE ingredients (
    id SERIAL PRIMARY KEY,
    supplier_id INTEGER REFERENCES suppliers(id) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    unit_measure unit_measure NOT NULL DEFAULT 'KG',
    cost_per_unit DECIMAL(10, 4) NOT NULL,
    current_stock DECIMAL(10, 3) DEFAULT 0.000,
    minimum_stock_alert DECIMAL(10, 3) DEFAULT 0.000,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_ingredients_supplier_id ON ingredients(supplier_id);
CREATE INDEX idx_ingredients_name ON ingredients(name);

-- 6. ALLERGENS (Tabella di decodifica allergeni)
CREATE TABLE allergens (
    id SERIAL PRIMARY KEY,
    code VARCHAR(10) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    description TEXT
);

-- Inserimento allergeni standard EU
INSERT INTO allergens (code, name, description) VALUES
('GLU', 'Glutine', 'Cereali contenenti glutine'),
('CRU', 'Crostacei', 'Crostacei e prodotti derivati'),
('EGG', 'Uova', 'Uova e prodotti derivati'),
('FSH', 'Pesce', 'Pesce e prodotti derivati'),
('PNT', 'Arachidi', 'Arachidi e prodotti derivati'),
('SOY', 'Soia', 'Soia e prodotti derivati'),
('MLK', 'Latte', 'Latte e prodotti derivati (lattosio)'),
('NUT', 'Frutta a guscio', 'Mandorle, nocciole, noci, etc.'),
('CEL', 'Sedano', 'Sedano e prodotti derivati'),
('MUS', 'Senape', 'Senape e prodotti derivati'),
('SES', 'Sesamo', 'Semi di sesamo e prodotti derivati'),
('SO2', 'Solfiti', 'Anidride solforosa e solfiti'),
('LUP', 'Lupini', 'Lupini e prodotti derivati'),
('MOL', 'Molluschi', 'Molluschi e prodotti derivati');

-- 7. INGREDIENT_ALLERGENS (Sicurezza Alimentare - M:N)
CREATE TABLE ingredient_allergens (
    ingredient_id INTEGER NOT NULL REFERENCES ingredients(id) ON DELETE CASCADE,
    allergen_id INTEGER NOT NULL REFERENCES allergens(id) ON DELETE CASCADE,
    PRIMARY KEY (ingredient_id, allergen_id)
);

-- ============================================================
-- 🍝 AREA 3: CATALOGO E RICETTE (Il Prodotto)
-- ============================================================

-- 8. PRODUCT_CATEGORIES
CREATE TABLE product_categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    display_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 9. PRODUCTS (Piatti Vendibili)
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    category_id INTEGER REFERENCES product_categories(id) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(10, 2) NOT NULL,
    servings INTEGER DEFAULT 1,
    image_url VARCHAR(500),
    is_active BOOLEAN DEFAULT TRUE,
    shelf_life_days INTEGER DEFAULT 3,
    preparation_time_minutes INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_products_category_id ON products(category_id);
CREATE INDEX idx_products_is_active ON products(is_active);

-- 10. PRODUCT_RECIPES (Distinta Base / Bill of Materials)
CREATE TABLE product_recipes (
    id SERIAL PRIMARY KEY,
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    ingredient_id INTEGER NOT NULL REFERENCES ingredients(id) ON DELETE RESTRICT,
    quantity_required DECIMAL(10, 4) NOT NULL,
    notes VARCHAR(255),
    UNIQUE(product_id, ingredient_id)
);

CREATE INDEX idx_product_recipes_product_id ON product_recipes(product_id);
CREATE INDEX idx_product_recipes_ingredient_id ON product_recipes(ingredient_id);

-- ============================================================
-- 📅 AREA 4: PIANIFICAZIONE E ABBONAMENTI (Commerciale)
-- ============================================================

-- 11. WEEKLY_MENUS (Calendario Menu)
CREATE TYPE menu_status AS ENUM ('DRAFT', 'PUBLISHED', 'ARCHIVED');

CREATE TABLE weekly_menus (
    id SERIAL PRIMARY KEY,
    year INTEGER NOT NULL,
    week_number INTEGER NOT NULL CHECK (week_number BETWEEN 1 AND 53),
    title VARCHAR(255),
    description TEXT,
    status menu_status DEFAULT 'DRAFT',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    published_at TIMESTAMP WITH TIME ZONE,
    UNIQUE(year, week_number)
);

CREATE INDEX idx_weekly_menus_year_week ON weekly_menus(year, week_number);

-- 12. MENU_AVAILABILITIES (Cosa vendo questa settimana)
CREATE TABLE menu_availabilities (
    id SERIAL PRIMARY KEY,
    weekly_menu_id INTEGER NOT NULL REFERENCES weekly_menus(id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    available_quantity INTEGER,
    day_of_week INTEGER CHECK (day_of_week BETWEEN 1 AND 7),
    special_price DECIMAL(10, 2),
    UNIQUE(weekly_menu_id, product_id, day_of_week)
);

CREATE INDEX idx_menu_availabilities_menu_id ON menu_availabilities(weekly_menu_id);

-- 13. SUBSCRIPTION_PLANS (Offerte Abbonamento)
CREATE TYPE billing_interval AS ENUM ('WEEKLY', 'BIWEEKLY', 'MONTHLY');

CREATE TABLE subscription_plans (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(10, 2) NOT NULL,
    billing_interval billing_interval NOT NULL DEFAULT 'WEEKLY',
    credits_included INTEGER DEFAULT 1,
    stripe_price_id VARCHAR(255),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 14. USER_SUBSCRIPTIONS (Abbonamenti Attivi)
CREATE TYPE subscription_status AS ENUM ('ACTIVE', 'PAUSED', 'CANCELLED', 'PAST_DUE', 'TRIALING');

CREATE TABLE user_subscriptions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plan_id INTEGER NOT NULL REFERENCES subscription_plans(id) ON DELETE RESTRICT,
    status subscription_status DEFAULT 'ACTIVE',
    current_period_start TIMESTAMP WITH TIME ZONE,
    current_period_end TIMESTAMP WITH TIME ZONE,
    credits_remaining INTEGER DEFAULT 0,
    auto_renew BOOLEAN DEFAULT TRUE,
    paused_at TIMESTAMP WITH TIME ZONE,
    cancelled_at TIMESTAMP WITH TIME ZONE,
    stripe_subscription_id VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_user_subscriptions_user_id ON user_subscriptions(user_id);
CREATE INDEX idx_user_subscriptions_status ON user_subscriptions(status);

-- ============================================================
-- 🛵 AREA 5: ORDINI E LOGISTICA
-- ============================================================

-- 15. ORDERS (Testata Ordine)
CREATE TYPE order_status AS ENUM ('CREATED', 'PAID', 'CONFIRMED', 'IN_KITCHEN', 'READY', 'OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED');
CREATE TYPE payment_method AS ENUM ('WALLET', 'CREDIT_CARD', 'SUBSCRIPTION_CREDIT', 'CASH');

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    subscription_id INTEGER REFERENCES user_subscriptions(id) ON DELETE SET NULL,
    status order_status DEFAULT 'CREATED',
    total_amount DECIMAL(10, 2) NOT NULL,
    discount_amount DECIMAL(10, 2) DEFAULT 0.00,
    final_amount DECIMAL(10, 2) NOT NULL,
    payment_method payment_method,
    delivery_address_id INTEGER REFERENCES user_addresses(id) ON DELETE SET NULL,
    delivery_slot_start TIMESTAMP WITH TIME ZONE,
    delivery_slot_end TIMESTAMP WITH TIME ZONE,
    notes TEXT,
    stripe_payment_intent_id VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    paid_at TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_orders_user_id ON orders(user_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_delivery_slot ON orders(delivery_slot_start);
CREATE INDEX idx_orders_created_at ON orders(created_at);

-- 16. ORDER_ITEMS (Righe Ordine)
CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL DEFAULT 1,
    unit_price_at_purchase DECIMAL(10, 2) NOT NULL,
    product_name_at_purchase VARCHAR(255) NOT NULL,
    notes VARCHAR(255)
);

CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_order_items_product_id ON order_items(product_id);

-- Aggiungi FK per wallet_transactions -> orders (dopo creazione tabella orders)
ALTER TABLE wallet_transactions 
    ADD CONSTRAINT fk_wallet_transactions_order 
    FOREIGN KEY (reference_order_id) REFERENCES orders(id) ON DELETE SET NULL;

-- ============================================================
-- 📊 VISTE UTILI
-- ============================================================

-- Vista: Food Cost per Prodotto
CREATE VIEW v_product_food_cost AS
SELECT 
    p.id AS product_id,
    p.name AS product_name,
    p.price AS selling_price,
    COALESCE(SUM(pr.quantity_required * i.cost_per_unit), 0) AS food_cost,
    p.price - COALESCE(SUM(pr.quantity_required * i.cost_per_unit), 0) AS gross_margin,
    CASE 
        WHEN p.price > 0 THEN 
            ROUND(((p.price - COALESCE(SUM(pr.quantity_required * i.cost_per_unit), 0)) / p.price) * 100, 2)
        ELSE 0 
    END AS margin_percentage
FROM products p
LEFT JOIN product_recipes pr ON p.id = pr.product_id
LEFT JOIN ingredients i ON pr.ingredient_id = i.id
GROUP BY p.id, p.name, p.price;

-- Vista: Allergeni per Prodotto (ereditati dagli ingredienti)
CREATE VIEW v_product_allergens AS
SELECT DISTINCT
    p.id AS product_id,
    p.name AS product_name,
    a.id AS allergen_id,
    a.code AS allergen_code,
    a.name AS allergen_name
FROM products p
JOIN product_recipes pr ON p.id = pr.product_id
JOIN ingredient_allergens ia ON pr.ingredient_id = ia.ingredient_id
JOIN allergens a ON ia.allergen_id = a.id
ORDER BY p.id, a.code;

-- Vista: Lista della Spesa (Ingredienti sotto soglia)
CREATE VIEW v_shopping_list AS
SELECT 
    i.id AS ingredient_id,
    i.name AS ingredient_name,
    s.company_name AS supplier_name,
    i.current_stock,
    i.minimum_stock_alert,
    i.unit_measure,
    i.cost_per_unit,
    (i.minimum_stock_alert - i.current_stock) AS quantity_to_order
FROM ingredients i
LEFT JOIN suppliers s ON i.supplier_id = s.id
WHERE i.current_stock < i.minimum_stock_alert
    AND i.is_active = TRUE
ORDER BY (i.minimum_stock_alert - i.current_stock) DESC;

-- Vista: Riepilogo Ordini per Produzione
CREATE VIEW v_kitchen_production_queue AS
SELECT 
    oi.product_id,
    p.name AS product_name,
    SUM(oi.quantity) AS total_quantity,
    o.delivery_slot_start::DATE AS delivery_date
FROM orders o
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id
WHERE o.status IN ('PAID', 'CONFIRMED', 'IN_KITCHEN')
GROUP BY oi.product_id, p.name, o.delivery_slot_start::DATE
ORDER BY o.delivery_slot_start::DATE, p.name;

-- ============================================================
-- 🔧 FUNZIONI E TRIGGER
-- ============================================================

-- Funzione: Aggiorna updated_at automaticamente
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger per updated_at
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_ingredients_updated_at
    BEFORE UPDATE ON ingredients
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_products_updated_at
    BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_subscriptions_updated_at
    BEFORE UPDATE ON user_subscriptions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_orders_updated_at
    BEFORE UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Funzione: Aggiorna wallet_balance dopo transazione
CREATE OR REPLACE FUNCTION update_wallet_balance()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE users 
    SET wallet_balance = wallet_balance + NEW.amount
    WHERE id = NEW.user_id;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER trigger_update_wallet_balance
    AFTER INSERT ON wallet_transactions
    FOR EACH ROW EXECUTE FUNCTION update_wallet_balance();

-- Funzione: Scala stock ingredienti quando ordine confermato
CREATE OR REPLACE FUNCTION deduct_ingredient_stock()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'CONFIRMED' AND OLD.status != 'CONFIRMED' THEN
        UPDATE ingredients i
        SET current_stock = current_stock - (
            SELECT COALESCE(SUM(pr.quantity_required * oi.quantity), 0)
            FROM order_items oi
            JOIN product_recipes pr ON oi.product_id = pr.product_id
            WHERE oi.order_id = NEW.id AND pr.ingredient_id = i.id
        )
        WHERE i.id IN (
            SELECT DISTINCT pr.ingredient_id
            FROM order_items oi
            JOIN product_recipes pr ON oi.product_id = pr.product_id
            WHERE oi.order_id = NEW.id
        );
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER trigger_deduct_stock_on_confirm
    AFTER UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION deduct_ingredient_stock();

-- ============================================================
-- ✅ SCHEMA COMPLETATO
-- ============================================================
-- Per eseguire: psql -U username -d kitchen4u -f schema.sql
-- ============================================================

-- Pantry Chef - Supabase Schema Migration
-- Run this in your Supabase SQL Editor to set up the database

-- ============================================
-- PANTRY ITEMS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS pantry_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    category TEXT NOT NULL DEFAULT 'other',
    quantity DOUBLE PRECISION NOT NULL DEFAULT 1,
    unit TEXT NOT NULL DEFAULT 'piece',
    expiry_date TIMESTAMPTZ,
    date_added TIMESTAMPTZ NOT NULL DEFAULT now(),
    notes TEXT,
    image_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_pantry_items_category ON pantry_items(category);
CREATE INDEX IF NOT EXISTS idx_pantry_items_expiry ON pantry_items(expiry_date);
CREATE INDEX IF NOT EXISTS idx_pantry_items_name ON pantry_items(name);

-- ============================================
-- RECIPES TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS recipes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    image_url TEXT,
    prep_time_minutes INT NOT NULL DEFAULT 0,
    cook_time_minutes INT NOT NULL DEFAULT 0,
    servings INT NOT NULL DEFAULT 4,
    difficulty TEXT NOT NULL DEFAULT 'easy',
    meal_type TEXT NOT NULL DEFAULT 'dinner',
    dietary_tags JSONB NOT NULL DEFAULT '[]'::jsonb,
    ingredients JSONB NOT NULL DEFAULT '[]'::jsonb,
    steps JSONB NOT NULL DEFAULT '[]'::jsonb,
    nutrition JSONB,
    source_url TEXT,
    is_favorite BOOLEAN NOT NULL DEFAULT false,
    times_cooked INT NOT NULL DEFAULT 0,
    last_cooked_date TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_recipes_meal_type ON recipes(meal_type);
CREATE INDEX IF NOT EXISTS idx_recipes_difficulty ON recipes(difficulty);
CREATE INDEX IF NOT EXISTS idx_recipes_favorite ON recipes(is_favorite) WHERE is_favorite = true;

-- ============================================
-- MEAL PLAN ENTRIES TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS meal_plan_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    date DATE NOT NULL,
    meal_type TEXT NOT NULL,
    recipe_id UUID REFERENCES recipes(id) ON DELETE SET NULL,
    custom_meal_name TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Ensure one entry per meal slot per day
    UNIQUE(date, meal_type)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_meal_plan_date ON meal_plan_entries(date);
CREATE INDEX IF NOT EXISTS idx_meal_plan_date_range ON meal_plan_entries(date) WHERE date >= CURRENT_DATE;

-- ============================================
-- SHOPPING ITEMS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS shopping_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    quantity DOUBLE PRECISION,
    unit TEXT,
    category TEXT NOT NULL DEFAULT 'other',
    is_checked BOOLEAN NOT NULL DEFAULT false,
    recipe_source TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_shopping_items_checked ON shopping_items(is_checked);
CREATE INDEX IF NOT EXISTS idx_shopping_items_category ON shopping_items(category);

-- ============================================
-- UPDATED_AT TRIGGER FUNCTION
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply updated_at triggers
CREATE TRIGGER update_pantry_items_updated_at
    BEFORE UPDATE ON pantry_items
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_recipes_updated_at
    BEFORE UPDATE ON recipes
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_meal_plan_entries_updated_at
    BEFORE UPDATE ON meal_plan_entries
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_shopping_items_updated_at
    BEFORE UPDATE ON shopping_items
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- ROW LEVEL SECURITY (RLS)
-- For personal use (no auth), we disable RLS
-- Enable and add policies if auth is added later
-- ============================================
ALTER TABLE pantry_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE recipes ENABLE ROW LEVEL SECURITY;
ALTER TABLE meal_plan_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE shopping_items ENABLE ROW LEVEL SECURITY;

-- Allow all operations for anonymous users (personal use)
CREATE POLICY "Allow all for anon" ON pantry_items FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all for anon" ON recipes FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all for anon" ON meal_plan_entries FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all for anon" ON shopping_items FOR ALL USING (true) WITH CHECK (true);

-- ============================================
-- JSONB STRUCTURE DOCUMENTATION
-- ============================================
-- 
-- recipes.ingredients JSONB format:
-- [
--   {
--     "name": "chicken breast",
--     "quantity": 2,
--     "unit": "pound",
--     "notes": "boneless, skinless",
--     "isOptional": false
--   }
-- ]
--
-- recipes.steps JSONB format:
-- [
--   {
--     "stepNumber": 1,
--     "instruction": "Preheat oven to 375°F",
--     "timerMinutes": null,
--     "tip": "Use convection if available"
--   }
-- ]
--
-- recipes.nutrition JSONB format:
-- {
--   "calories": 450,
--   "protein": 35,
--   "carbs": 40,
--   "fat": 15,
--   "fiber": 5
-- }
--
-- recipes.dietary_tags JSONB format:
-- ["glutenFree", "dairyFree", "highProtein"]

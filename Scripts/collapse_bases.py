#!/usr/bin/env python3
"""
Deterministic post-processor for catalog_bases.json.

Applies three passes:
  1. Within-category base merges (spelling dupes, over-specific bases)
  2. Cross-category dedup (bases appearing in multiple categories)
  3. Cleanup (remove empties, sort, stats)

No LLM calls — pure Python string transforms.
"""

import json
import shutil
import sys
from collections import defaultdict
from pathlib import Path

SCRIPTS_DIR = Path(__file__).parent
INPUT = SCRIPTS_DIR / "triage_output" / "catalog_bases.json"
BACKUP = SCRIPTS_DIR / "triage_output" / "catalog_bases_v1.json"
OUTPUT = INPUT  # overwrite in place

# ═══════════════════════════════════════════════════════════════════════════
# Pass 1: Within-category base merges
# Key = category, Value = dict mapping source_base → target_base
# When source merges into target, source's variants are absorbed into target.
# ═══════════════════════════════════════════════════════════════════════════

BASE_MERGES = {
    # ── Dairy & Eggs ──────────────────────────────────────────────────────
    "Dairy & Eggs": {
        # All named cheeses → "cheese"
        "american cheese": "cheese",
        "asiago cheese": "cheese",
        "blue cheese": "cheese",
        "bocconcini": "cheese",
        "brie": "cheese",
        "burrata": "cheese",
        "camembert": "cheese",
        "cheddar cheese": "cheese",
        "cheese blend": "cheese",
        "cheese spread": "cheese",
        "cheez whiz": "cheese",
        "chihuahua cheese": "cheese",
        "chèvre": "cheese",
        "cotija": "cheese",
        "english cheese": "cheese",
        "farmer cheese": "cheese",
        "feta": "cheese",
        "feta cheese": "cheese",
        "fontina": "cheese",
        "goat cheese": "cheese",
        "gorgonzola": "cheese",
        "gouda": "cheese",
        "grana padano": "cheese",
        "gruyère": "cheese",
        "halloumi": "cheese",
        "hard cheese": "cheese",
        "havarti cheese": "cheese",
        "jack cheese": "cheese",
        "jarlsberg cheese": "cheese",
        "longhorn cheese": "cheese",
        "manchego cheese": "cheese",
        "mexican cheese": "cheese",
        "mexican cheese blend": "cheese",
        "monterey jack cheese": "cheese",
        "mozzarella cheese": "cheese",
        "muenster cheese": "cheese",
        "neufchâtel": "cheese",
        "paneer": "cheese",
        "parmesan cheese": "cheese",
        "parmigiano-reggiano": "cheese",
        "pecorino": "cheese",
        "pecorino romano": "cheese",
        "pepper cheese": "cheese",
        "pepper jack cheese": "cheese",
        "processed cheese": "cheese",
        "provolone": "cheese",
        "queso fresco": "cheese",
        "ricotta salata": "cheese",
        "romano": "cheese",
        "romano cheese": "cheese",
        "roquefort": "cheese",
        "roquefort cheese": "cheese",
        "smoked gouda": "cheese",
        "stilton": "cheese",
        "string cheese": "cheese",
        "swiss cheese": "cheese",
        "tasty cheese": "cheese",
        "white cheese": "cheese",
        "yogurt cheese": "cheese",
        # Exceptions: cream cheese, cottage cheese, ricotta, mascarpone,
        # velveeta cheese, vegan cream cheese → stay as own bases.
        # Hyphen dupe
        "half-and-half": "half and half",
    },

    # ── Protein ───────────────────────────────────────────────────────────
    "Protein": {
        # Ground meats → base meat (ground is a form/facet)
        "ground beef": "beef",
        "ground sirloin": "beef",
        "ground chicken": "chicken",
        "ground lamb": "lamb",
        "ground meat": "meat",
        "ground veal": "veal",
        # Sausage variants → sausage
        "andouille sausage": "sausage",
        "breakfast sausage": "sausage",
        "chicken sausage": "sausage",
        "chinese sausage": "sausage",
        "hot sausage": "sausage",
        "polish sausage": "sausage",
        "smoked sausage": "sausage",
        "sausage link": "sausage",
        # Smoked variants → base protein
        "smoked bacon": "bacon",
        "smoked ham": "ham",
        "smoked salmon": "salmon",
        "smoked haddock": "haddock",
        # Bones → soup bone
        "beef bone": "soup bone",
        "chicken bone": "soup bone",
        "ham bone": "soup bone",
        "meat bone": "soup bone",
    },

    # ── Spices & Herbs ────────────────────────────────────────────────────
    "Spices & Herbs": {
        # Spelling / plural dupes
        "chives": "chive",
        "asafoetida": "asafetida",
        "chili flakes": "chili flake",
        "five-spice powder": "five spice powder",
        "pickling spices": "pickling spice",
        "monosodium glutamate": "msg",
        # Red pepper flakes consolidation
        "red chili flakes": "red pepper flakes",
        "red chili powder": "red pepper flakes",
        "chili flake": "red pepper flakes",
        # Chipotle consolidation
        "chipotle chile": "chipotle",
        "chipotle pepper": "chipotle",
        "chipotle powder": "chipotle",
        # Wasabi consolidation
        "wasabi paste": "wasabi",
        "wasabi powder": "wasabi",
        # Pumpkin spice consolidation
        "pumpkin spice": "pumpkin pie spice",
        "pie spice": "pumpkin pie spice",
        # Seasoning mix dupes
        "chili seasoning mix": "chili seasoning",
        "taco seasoning mix": "taco seasoning",
        # Ginger paste → ginger
        "ginger paste": "ginger",
        # Ancho consolidation
        "ancho chili": "ancho powder",
        # Coriander dupes
        "coriander leaf": "coriander",
        "coriander seed": "coriander",
        # Cumin dupe
        "cumin seed": "cumin",
        # Cardamom consolidation
        "black cardamom": "cardamom",
        "brown cardamom": "cardamom",
        # Allspice dupe
        "allspice berry": "allspice",
        # Cinnamon dupe
        "cinnamon stick": "cinnamon",
        # Italian seasoning consolidation
        "italian herb blend": "italian seasoning",
        "italian herb seasoning": "italian seasoning",
        # Peppercorn consolidation
        "green peppercorn": "peppercorn",
        "pink peppercorn": "peppercorn",
        "white peppercorn": "peppercorn",
        # Spice/spices/herbs dupes
        "spices": "spice",
        "mixed herbs": "herbs",
        # Paprika consolidation
        "spanish paprika": "paprika",
        "sweet paprika": "paprika",
        # Chinese five spice dupe
        "chinese five spice": "five spice powder",
        # White pepper → peppercorn? No, white pepper is distinct in cooking.
        # Keep white pepper separate.
    },

    # ── Condiments & Sauces ───────────────────────────────────────────────
    "Condiments & Sauces": {
        # A-1 / steak sauce consolidation
        "a-1 sauce": "steak sauce",
        "a.1. sauce": "steak sauce",
        "heinz 57 sauce": "steak sauce",
        # Chile/chili spelling
        "chile paste": "chili paste",
        "chile sauce": "chili sauce",
        # Chili garlic consolidation
        "chile garlic paste": "chili garlic sauce",
        "garlic chili sauce": "chili garlic sauce",
        # Rose water dupe
        "rosewater": "rose water",
        # Orange blossom dupe
        "orange flower water": "orange blossom water",
        # Rice vinegar consolidation
        "rice wine vinegar": "rice vinegar",
        "seasoned rice vinegar": "rice vinegar",
        # Horseradish consolidation
        "creamed horseradish": "horseradish sauce",
        "horseradish cream": "horseradish sauce",
        # Note: "horseradish" base stays (used as raw ingredient); 
        # horseradish sauce/cream are prepared condiments.
        # Spaghetti sauce dupe with marinara
        "spaghetti sauce": "marinara sauce",
        # Chipotle consolidation
        "chipotle paste": "chipotle sauce",
        # Wing sauce dupe
        "buffalo wing sauce": "wing sauce",
        # Onion soup mix dupe (keep in Condiments, remove from Canned later)
        # Chicken bouillon/stock powder consolidation
        "chicken stock powder": "chicken bouillon powder",
        "chicken soup base": "chicken bouillon powder",
        # Tamarind consolidation
        "tamarind concentrate": "tamarind paste",
        # Grenadine (keep here, will be removed from Beverages in cross-cat)
    },

    # ── Oils & Fats ───────────────────────────────────────────────────────
    "Oils & Fats": {
        # Cooking spray consolidation (7→1)
        "butter-flavored cooking spray": "cooking spray",
        "canola oil cooking spray": "cooking spray",
        "nonstick vegetable oil spray": "cooking spray",
        "olive oil cooking spray": "cooking spray",
        "olive oil spray": "cooking spray",
        "vegetable oil cooking spray": "cooking spray",
        "vegetable oil spray": "cooking spray",
        # Sesame oil consolidation
        "dark sesame oil": "sesame oil",
        "toasted sesame oil": "sesame oil",
        # Generic oil consolidation
        "oil": "cooking oil",
        "neutral oil": "cooking oil",
        # Bacon fat dupe
        "bacon grease": "bacon drippings",
        # Drippings (generic) → keep as-is (could be any meat)
    },

    # ── Baking & Sweeteners ───────────────────────────────────────────────
    "Baking & Sweeteners": {
        # Arrowroot consolidation
        "arrowroot flour": "arrowroot",
        "arrowroot starch": "arrowroot",
        # Dried coconut consolidation
        "desiccated coconut": "shredded coconut",
        "dried coconut": "shredded coconut",
        # Chocolate chips consolidation
        "dark chocolate chips": "chocolate chips",
        "milk chocolate chips": "chocolate chips",
        "white chocolate chips": "chocolate chips",
        # Sugar substitute consolidation
        "artificial sweetener": "sugar substitute",
        "erythritol": "sugar substitute",
        "liquid sweetener": "sugar substitute",
        "splenda": "sugar substitute",
        "splenda sugar blend": "sugar substitute",
        "stevia": "sugar substitute",
        "sucralose": "sugar substitute",
        "sweetener": "sugar substitute",
        "swerve sweetener": "sugar substitute",
        "truvia": "sugar substitute",
        "xylitol": "sugar substitute",
        # Gelatin dessert consolidation (flavored → gelatin dessert)
        "cherry gelatin": "gelatin dessert",
        "lemon gelatin": "gelatin dessert",
        "lime gelatin": "gelatin dessert",
        "orange gelatin": "gelatin dessert",
        "raspberry gelatin": "gelatin dessert",
        "strawberry gelatin": "gelatin dessert",
        "strawberry gelatin dessert": "gelatin dessert",
        "peach gelatin dessert": "gelatin dessert",
        # Marshmallow creme dupe
        "marshmallow fluff": "marshmallow creme",
        # Cocoa powder consolidation
        "dutch-process cocoa powder": "cocoa powder",
        "cacao powder": "cocoa powder",
        # Chocolate consolidation (base chocolate products)
        "baking chocolate": "chocolate",
        "bittersweet chocolate": "chocolate",
        "semisweet chocolate": "chocolate",
        "milk chocolate": "chocolate",
        "white chocolate": "chocolate",
        "chocolate bar": "chocolate",
        "chocolate square": "chocolate",
        # Agave dupe
        "agave syrup": "agave nectar",
        # Pancake syrup → maple syrup
        "pancake syrup": "maple syrup",
        # Vanilla bean → vanilla
        "vanilla bean": "vanilla",
        # Sprinkle/sprinkles
        "sprinkle": "sprinkles",
        # Tapioca consolidation
        "tapioca starch": "tapioca",
        "tapioca pearl": "tapioca",
        "instant tapioca": "tapioca",
        # Pudding consolidation
        "chocolate pudding mix": "pudding mix",
        "vanilla pudding mix": "pudding mix",
        "pistachio pudding mix": "pudding mix",
        "lemon pudding mix": "pudding mix",
        "butterscotch pudding": "pudding mix",
        "pistachio pudding": "pudding mix",
        "lemon pudding": "pudding mix",
        "pudding": "pudding mix",
        # Frosting consolidation
        "chocolate frosting": "frosting",
        "cream cheese frosting": "frosting",
        "vanilla frosting": "frosting",
        "icing": "frosting",
        # Chocolate hazelnut spread (keep — distinct product; also in Condiments)
        # Brown sugar substitute → sugar substitute
        "brown sugar substitute": "sugar substitute",
        # Ganache → chocolate ganache (keep one)
        "ganache": "chocolate ganache",
        # Glaze / strawberry glaze
        "strawberry glaze": "glaze",
        # Streusel / ice cream topping → keep separate
        # Jam / jelly (keep separate — different products)
        # Strawberry jam → jam? No, it's a specific product. Keep.
        # Raisin and currant → drop (compound)
        # Cookie / cookie dough / cookie mix consolidation
        "cookie dough": "cookie",
        "cookie mix": "cookie",
        # Cake / cake mix consolidation
        "cake mix": "cake",
        # Brownie mix → keep (distinct product)
        # Fructose → sugar (no, keep — distinct sweetener)
        # Cacao nibs → keep (distinct from cocoa powder)
        # Honey sugar / honey syrup → honey
        "honey sugar": "honey",
        "honey syrup": "honey",
        # Sugar syrup / simple syrup / syrup
        "sugar syrup": "simple syrup",
        "syrup": "simple syrup",
        # White syrup → simple syrup
        "white syrup": "simple syrup",
        # Caramel syrup / caramel topping → caramel
        "caramel syrup": "caramel",
        "caramel topping": "caramel",
        # Chocolate fudge topping → chocolate sauce (but that's in Condiments)
        # Keep chocolate fudge topping in Baking
        # Coconut syrup / coconut nectar
        "coconut nectar": "coconut sugar",
        "coconut syrup": "coconut sugar",
        # Rum extract / rum flavoring
        "rum flavoring": "rum extract",
        # Lemon extract / lemon flavoring
        "lemon flavoring": "lemon extract",
        # Coconut extract / coconut flavoring
        "coconut flavoring": "coconut extract",
        # Vanilla sugar → vanilla
        "vanilla sugar": "vanilla",
        # Vanilla wafer → keep (distinct snack/baking product)
        # Chocolate wafer → keep
        # Shortbread cookie → cookie
        "shortbread cookie": "cookie",
        # Chocolate chip cookie → cookie
        "chocolate chip cookie": "cookie",
        # Chocolate cookie → cookie
        "chocolate cookie": "cookie",
        # Mixed citrus peel / candied peel
        "mixed citrus peel": "candied peel",
        # Cocoa mix / chocolate mix
        "chocolate mix": "cocoa mix",
        # Pectin / fruit pectin
        "fruit pectin": "pectin",
        # Malt powder / malt syrup
        "malt syrup": "malt powder",
        # Cornmeal (also in Grains!) - will handle in cross-cat
        # Treacle / black treacle
        "black treacle": "treacle",
        # Sparkling sugar → sprinkles
        "sparkling sugar": "sprinkles",
        # Chocolate candies → keep (m&ms etc)
        # Chocolate curl → chocolate (decorative form)
        "chocolate curl": "chocolate",
        # Butter chips → keep
        # Rice syrup → keep
    },

    # ── Beverages ─────────────────────────────────────────────────────────
    "Beverages": {
        # Sparkling water consolidation (6→1)
        "carbonated water": "sparkling water",
        "club soda": "sparkling water",
        "seltzer": "sparkling water",
        "seltzer water": "sparkling water",
        "soda water": "sparkling water",
        # Tea consolidation
        "tea bag": "tea",
        "tea leaf": "tea",
        "instant tea": "tea",
        # Matcha consolidation
        "matcha powder": "matcha",
        "green tea powder": "matcha",
        # Lemonade consolidation
        "lemonade concentrate": "lemonade",
        "lemonade mix": "lemonade",
        "pink lemonade": "lemonade",
        # Coffee consolidation
        "instant coffee": "coffee",
        "coffee bean": "coffee",
        # Espresso consolidation
        "instant espresso": "espresso",
        # 7 up / lemon-lime soda / lemon lime beverage
        "7 up": "lemon-lime soda",
        "lemon lime beverage": "lemon-lime soda",
        # Apricot juice / apricot nectar
        "apricot nectar": "apricot juice",
        # Mango juice / mango nectar
        "mango nectar": "mango juice",
        # Peach juice / peach nectar
        "peach nectar": "peach juice",
        # Pear juice / pear nectar
        "pear nectar": "pear juice",
        # Fruit juice / juice
        "juice": "fruit juice",
        # Fruit nectar → fruit juice
        "fruit nectar": "fruit juice",
        # Cranberry juice cocktail → cranberry juice
        "cranberry juice cocktail": "cranberry juice",
    },

    # ── Canned & Jarred ───────────────────────────────────────────────────
    "Canned & Jarred": {
        # Bouillon consolidation by protein
        "beef bouillon cube": "beef bouillon",
        "chicken bouillon cube": "chicken bouillon",
        "chicken bouillon granule": "chicken bouillon",
        "vegetable bouillon cube": "vegetable bouillon",
        "bouillon cube": "bouillon",
        # Stock/broth/base consolidation
        "beef stock": "beef broth",
        "beef base": "beef broth",
        "beef stock cube": "beef broth",
        "chicken stock": "chicken broth",
        "chicken base": "chicken broth",
        "chicken stock cube": "chicken broth",
        "vegetable stock powder": "vegetable stock",
        # Generic stock/broth
        "stock": "broth",
        # Canned mushroom dupe
        "canned sliced mushroom": "canned mushroom",
        # Passata dupe
        "tomato passata": "passata",
        # Pumpkin filling dupe
        "pumpkin pie mix": "pumpkin pie filling",
        # Marinated artichoke dupe
        "marinated artichoke hearts": "marinated artichoke",
        # Cream style corn / creamed corn
        "cream style corn": "creamed corn",
        # Spaghetti sauce / spaghetti sauce mix
        "spaghetti sauce mix": "spaghetti sauce",
        # Chicken soup dupes
        "chicken rice soup": "chicken and rice soup",
        "chicken-flavored soup powder": "chicken soup",
        # Cheese soup dupe
        "cheddar cheese soup": "cheese soup",
        # Soup mix / vegetable soup mix
        "vegetable soup mix": "soup mix",
        # Cranberry sauce dupes
        "jellied cranberry sauce": "cranberry sauce",
        "whole berry cranberry sauce": "cranberry sauce",
        # Onion soup mix — keep (distinct product, used as seasoning)
        # Condensed cream of mushroom / cream of mushroom soup — keep both?
        # Actually merge: condensed is just the form
        "condensed cream of mushroom soup": "cream of mushroom soup",
        # Cream of mushroom chicken soup → cream of mushroom soup
        "cream of mushroom chicken soup": "cream of mushroom soup",
        # Condensed tomato soup → tomato soup
        "condensed tomato soup": "tomato soup",
        # Broccoli cheese soup → cheese soup? No, distinct. Keep.
        # Broccoli soup / cream of broccoli soup
        "broccoli soup": "cream of broccoli soup",
        # Turkey broth / turkey stock
        "turkey stock": "turkey broth",
        # Lamb stock → keep (no lamb broth counterpart)
        # Veal stock → keep
        # Seafood stock → keep
        # Shrimp stock / shrimp soup — keep separate
        # Fish stock → keep
        # Mushroom broth / mushroom soup — keep separate
        # Fruit preserve / preserve → keep one
        "preserve": "fruit preserve",
        # Pie filling (generic) — keep
        # Strawberry gelatin — will be handled in cross-cat dedup
    },

    # ── Pasta & Noodles ───────────────────────────────────────────────────
    "Pasta & Noodles": {
        "cheese ravioli": "ravioli",
        "cheese tortellini": "tortellini",
        "potato gnocchi": "gnocchi",
        "glass noodles": "bean thread noodle",
        # Chinese noodle / chinese egg noodle
        "chinese noodle": "chinese egg noodle",
        # Mein noodle / chow mein noodle
        "mein noodle": "chow mein noodle",
        # Rice vermicelli / vermicelli → keep separate (different products)
        # Short pasta → pasta
        "short pasta": "pasta",
        # Spaghettini → spaghetti
        "spaghettini": "spaghetti",
    },

    # ── Nuts & Seeds ──────────────────────────────────────────────────────
    "Nuts & Seeds": {
        "flaxseed": "flax seed",
        # flaxseed meal → keep (distinct from whole flax seed)
        # sesame paste → tahini? tahini is in Condiments, keep sesame paste here
    },

    # ── Legumes & Beans ───────────────────────────────────────────────────
    "Legumes & Beans": {
        "broad bean": "fava bean",
        "puy lentil": "french lentil",
        # Butter bean / lima bean (same thing)
        "butter bean": "lima bean",
    },

    # ── Snacks ────────────────────────────────────────────────────────────
    "Snacks": {
        "pretzel stick": "pretzel",
        "pretzel twist": "pretzel",
        # Chocolate wafer / chocolate wafer cookie
        "chocolate wafer cookie": "chocolate wafer",
        # Toffee / toffee bar
        "toffee bar": "toffee",
    },

    # ── Breads & Bakery ───────────────────────────────────────────────────
    "Breads & Bakery": {
        # Pie crust consolidation
        "pie crust mix": "pie crust",
        "pie dough": "pie crust",
        "cracker pie crust": "pie crust",
        # Stuffing mix → stuffing
        "stuffing mix": "stuffing",
        # Graham cracker crumb → graham cracker crust
        "graham cracker crumb": "graham cracker crust",
        # Tostada / tostada shell
        "tostada": "tostada shell",
    },

    # ── Alcohol & Spirits ─────────────────────────────────────────────────
    "Alcohol & Spirits": {
        # Red wine varietals → red wine
        "cabernet sauvignon wine": "red wine",
        "burgundy wine": "red wine",
        "merlot": "red wine",
        "pinot noir": "red wine",
        # White wine varietals → white wine
        "chardonnay": "white wine",
        "riesling wine": "white wine",
        "chablis": "white wine",
        "sauternes": "white wine",
        "sweet white wine": "white wine",
        # Sparkling wine consolidation
        "champagne": "sparkling wine",
        "prosecco": "sparkling wine",
        # Scotch dupe
        "scotch whisky": "scotch",
        # Beer consolidation
        "brown ale": "ale",
        "pale ale": "ale",
        "lager beer": "beer",
        "light beer": "beer",
        "dark beer": "beer",
        # Stout consolidation
        "guinness stout": "stout",
        # Dry wine → wine
        "dry wine": "wine",
        # Liqueur dupes
        "almond liqueur": "amaretto",
        "hazelnut liqueur": "frangelico",
        "coffee liqueur": "kahlua",
        "irish cream liqueur": "baileys irish cream",
        "cassis liqueur": "crème de cassis",
        # Crème de menthe dupe
        "green crème de menthe": "crème de menthe",
        # Crème de cacao dupe
        "white crème de cacao": "crème de cacao",
        # Port dupe
        "ruby port": "port",
        # Sherry consolidation
        "cream sherry": "sherry",
        "sweet sherry": "sherry",
        # cooking sherry stays separate (it's a cooking product)
        # Vermouth consolidation
        "sweet vermouth": "vermouth",
        "white vermouth": "vermouth",
        # Vanilla vodka → vodka
        "vanilla vodka": "vodka",
        # Generic alcohol/liquor
        "alcohol": "liquor",
        # Coconut rum / dark rum / spiced rum / white rum → rum
        "coconut rum": "rum",
        "dark rum": "rum",
        "spiced rum": "rum",
        "white rum": "rum",
        # Rye whiskey → whiskey
        "rye whiskey": "whiskey",
        # Schnapps consolidation
        "butterscotch schnapps": "schnapps",
        "peach schnapps": "schnapps",
        "peppermint schnapps": "schnapps",
    },

    # ── Produce ───────────────────────────────────────────────────────────
    "Produce": {
        # Chili → pepper naming normalization
        "anaheim chili": "anaheim pepper",
        "habanero chili": "habanero pepper",
        "serrano chili": "serrano pepper",
        "chipotle chili": "chipotle",  # if present
        "fresno chile": "fresno pepper",
        # Lettuce consolidation
        "romaine lettuce": "lettuce",
        "leaf lettuce": "lettuce",
        # Mixed greens consolidation
        "salad green": "mixed greens",
        "salad greens": "mixed greens",
        "mesclun": "mixed greens",
        "spring mix": "mixed greens",
        "spring green": "mixed greens",
        # Snap pea consolidation
        "sugar snap pea": "snap pea",
        "pea pod": "snap pea",
        # Daikon dupe
        "daikon radish": "daikon",
        # Swiss chard / chard
        "swiss chard": "chard",
        # Greens (generic) → keep as-is
        # Jalapeño dupe
        "jalapeño chili": "jalapeño",
        # Green chile → chili pepper? Keep as green chile (refers to canned style)
        # Corn husk → keep (for tamales)
        # Pomegranate / pomegranate seed
        "pomegranate seed": "pomegranate",
        # Tamarind / tamarind pulp
        "tamarind pulp": "tamarind",
        # Thai chile / thai chili pepper
        "thai chili pepper": "thai chile",
        # Pimiento / pimento
        "pimiento": "pimento",
        # Coleslaw / coleslaw mix / slaw mix
        "coleslaw": "coleslaw mix",
        "slaw mix": "coleslaw mix",
        # Broccoli slaw → keep
        # Citrus fruit / citrus zest → keep separate
        # Mixed dried fruit → keep (distinct from "dried fruit" in Snacks)
        # Raisin and cranberry / raisin and date → drop (compound entries)
        # Lime and lemon → drop (compound)
        # Berry (generic) → keep
        # Blood orange juice → keep (distinct from blood orange)
        # Meyer lemon juice → keep (distinct from meyer lemon)
        # Mushroom consolidation (keep named varieties separate — genuinely different)
        # Brown mushroom / cremini mushroom → they're the same thing
        "brown mushroom": "cremini mushroom",
        # Guajillo chili → guajillo pepper? Actually guajillo chili is the common name. Keep.
        # Pasilla chile → keep (common name)
        # Poblano / poblano pepper
        "poblano": "poblano pepper",
        # Cuban pepper → keep
        # Semi-dried tomato / sun-dried tomato → keep separate (different products)
        # Persimmon / persimmon pulp
        "persimmon pulp": "persimmon",
        # Raspberry / raspberry purée
        "raspberry purée": "raspberry",
        # Strawberry / strawberry purée
        "strawberry purée": "strawberry",
        # Potato / potato purée
        "potato purée": "potato",
    },

    # ── Grains & Cereals ──────────────────────────────────────────────────
    "Grains & Cereals": {
        # Cornmeal / cornmeal mix
        "cornmeal mix": "cornmeal",
        # Stuffing mix (also in Breads!) - handle in cross-cat
        # Tapioca / tapioca flour — keep (baking has tapioca too, cross-cat)
        # Rice flour (also in Baking!) - cross-cat
        # Hominy (also in Canned!) - cross-cat
    },

    # ── Frozen Foods ──────────────────────────────────────────────────────
    "Frozen Foods": {
        # Sherbet (also in Baking!) → handled in cross-cat
    },

    # ── Other ─────────────────────────────────────────────────────────────
    "Other": {
        # msg → remove from Other (canonical home is Spices)
        # coffee creamer → keep (also in Dairy cross-cat)
        # pectin / fruit pectin → will be handled via cross-cat
        "fruit pectin": "pectin",
    },
}

# Bases to DROP entirely (compound junk entries)
DROP_BASES = {
    "Nuts & Seeds": {"pecan and walnut", "walnut and almond"},
    "Produce": {"raisin and cranberry", "raisin and date", "lime and lemon", "peas and carrots"},
    "Baking & Sweeteners": {"raisin and currant"},
}

# ═══════════════════════════════════════════════════════════════════════════
# Pass 2: Cross-category dedup
# base_name → canonical category (remove from all others)
# ═══════════════════════════════════════════════════════════════════════════

CANONICAL_CATEGORY = {
    "horseradish": "Condiments & Sauces",
    "chocolate syrup": "Condiments & Sauces",
    "graham cracker": "Snacks",
    "shredded coconut": "Baking & Sweeteners",
    "dried coconut": "Baking & Sweeteners",
    "pork and beans": "Canned & Jarred",
    "cracker": "Snacks",
    "strawberry gelatin": "Baking & Sweeteners",
    "marshmallow": "Baking & Sweeteners",
    "cookie": "Baking & Sweeteners",
    "amaretti cookie": "Snacks",
    "msg": "Spices & Herbs",
    "grenadine": "Condiments & Sauces",
    "coffee creamer": "Dairy & Eggs",
    "cornmeal": "Grains & Cereals",
    "rice flour": "Baking & Sweeteners",
    "hominy": "Grains & Cereals",
    "sherbet": "Frozen Foods",
    "stuffing mix": "Breads & Bakery",  # after merge → "stuffing"
    "stuffing": "Breads & Bakery",
    "popcorn": "Snacks",
    "cake": "Baking & Sweeteners",
    "celery": "Produce",
    "garlic": "Produce",
    "ginger": "Produce",
    "onion soup mix": "Canned & Jarred",
    "spaghetti sauce": "Canned & Jarred",
    "marinara sauce": "Canned & Jarred",
    "pectin": "Baking & Sweeteners",
    "olive": "Produce",
    "corn": "Produce",
    "coconut": "Produce",
    "toffee": "Snacks",
    "chocolate hazelnut spread": "Condiments & Sauces",
}


def load_catalog(path):
    """Load catalog_bases.json and return dict of {category: [entries]}."""
    with open(path) as f:
        return json.load(f)


def merge_entry(target_entry, source_entry):
    """Merge source's base+variants into target's variants."""
    all_source_names = {source_entry["base"]}
    all_source_names.update(source_entry.get("variants", []))

    existing = {target_entry["base"]}
    existing.update(target_entry.get("variants", []))

    new_variants = all_source_names - existing - {target_entry["base"]}
    if new_variants:
        current_variants = set(target_entry.get("variants", []))
        current_variants.update(new_variants)
        target_entry["variants"] = sorted(current_variants)


def pass1_within_category_merges(catalog):
    """Apply BASE_MERGES within each category."""
    stats = {}
    for cat, merges in BASE_MERGES.items():
        if cat not in catalog or not merges:
            continue

        entries = catalog[cat]
        before_count = len(entries)

        # Build lookup: base_name → entry
        by_base = {e["base"]: e for e in entries}

        # Track which bases get absorbed
        absorbed = set()

        for source_base, target_base in merges.items():
            if source_base not in by_base:
                continue  # source doesn't exist, skip

            # Ensure target entry exists
            if target_base not in by_base:
                # Create the target entry (it might be a new base name)
                target_entry = {"base": target_base}
                by_base[target_base] = target_entry
                entries.append(target_entry)

            # Merge source into target
            merge_entry(by_base[target_base], by_base[source_base])
            absorbed.add(source_base)

        # Remove absorbed entries
        catalog[cat] = [e for e in entries if e["base"] not in absorbed]
        after_count = len(catalog[cat])
        if before_count != after_count:
            stats[cat] = (before_count, after_count)

    return stats


def pass1_drop_bases(catalog):
    """Remove compound/junk base entries."""
    stats = {}
    for cat, to_drop in DROP_BASES.items():
        if cat not in catalog:
            continue
        before = len(catalog[cat])
        catalog[cat] = [e for e in catalog[cat] if e["base"] not in to_drop]
        after = len(catalog[cat])
        if before != after:
            stats[cat] = (before, after)
    return stats


def pass2_cross_category_dedup(catalog):
    """Remove bases from non-canonical categories, merging variants."""
    moves = []

    for base_name, canon_cat in CANONICAL_CATEGORY.items():
        for cat in list(catalog.keys()):
            if cat == canon_cat:
                continue

            # Find this base in the non-canonical category
            entry_idx = None
            for i, e in enumerate(catalog[cat]):
                if e["base"] == base_name:
                    entry_idx = i
                    break

            if entry_idx is None:
                continue

            removed_entry = catalog[cat].pop(entry_idx)

            # Merge into canonical category if it exists there
            if canon_cat in catalog:
                canon_entries = {e["base"]: e for e in catalog[canon_cat]}
                if base_name in canon_entries:
                    merge_entry(canon_entries[base_name], removed_entry)
                else:
                    catalog[canon_cat].append(removed_entry)

            moves.append((base_name, cat, canon_cat))

    return moves


def pass3_cleanup(catalog):
    """Remove empty categories, sort entries, compute stats."""
    # Remove empty categories
    empty_cats = [cat for cat, entries in catalog.items() if not entries]
    for cat in empty_cats:
        del catalog[cat]

    # Sort entries within each category
    for cat in catalog:
        # Also clean up variants: remove base name from variants if accidentally there
        for entry in catalog[cat]:
            if "variants" in entry:
                entry["variants"] = sorted(
                    v for v in entry["variants"] if v != entry["base"]
                )
                if not entry["variants"]:
                    del entry["variants"]

        catalog[cat] = sorted(catalog[cat], key=lambda e: e["base"])

    return catalog


def main():
    print(f"Loading {INPUT}...")
    catalog = load_catalog(INPUT)

    # Count before
    total_before = sum(len(entries) for entries in catalog.values())
    print(f"Before: {total_before} bases in {len(catalog)} categories\n")

    # Backup
    if not BACKUP.exists():
        shutil.copy2(INPUT, BACKUP)
        print(f"Backed up to {BACKUP}")
    else:
        print(f"Backup already exists at {BACKUP}")

    # ── Pass 1: Within-category merges ──────────────────────────────────
    print("\n=== Pass 1: Within-category base merges ===")
    merge_stats = pass1_within_category_merges(catalog)
    for cat, (before, after) in sorted(merge_stats.items()):
        print(f"  {cat:<25s} {before:>4} → {after:>4}  (-{before - after})")

    drop_stats = pass1_drop_bases(catalog)
    for cat, (before, after) in sorted(drop_stats.items()):
        print(f"  {cat:<25s} {before:>4} → {after:>4}  (dropped {before - after})")

    mid_total = sum(len(entries) for entries in catalog.values())
    print(f"\n  After pass 1: {mid_total} bases")

    # ── Pass 2: Cross-category dedup ────────────────────────────────────
    print("\n=== Pass 2: Cross-category dedup ===")
    moves = pass2_cross_category_dedup(catalog)
    for base_name, from_cat, to_cat in moves:
        print(f"  '{base_name}': {from_cat} → {to_cat}")

    cross_total = sum(len(entries) for entries in catalog.values())
    print(f"\n  After pass 2: {cross_total} bases")

    # ── Pass 3: Cleanup ─────────────────────────────────────────────────
    print("\n=== Pass 3: Cleanup ===")
    catalog = pass3_cleanup(catalog)

    total_after = sum(len(entries) for entries in catalog.values())
    total_variants = sum(
        len(e.get("variants", [])) for entries in catalog.values() for e in entries
    )

    print(f"\n{'='*60}")
    print(f"FINAL: {total_before} → {total_after} bases  ({total_before - total_after} eliminated)")
    print(f"Total variants tracked: {total_variants}")
    print(f"{'='*60}")
    for cat in sorted(catalog.keys()):
        print(f"  {cat:<25s} {len(catalog[cat]):>4} bases")

    # Write output
    with open(OUTPUT, "w") as f:
        json.dump(catalog, f, indent=2, ensure_ascii=False)
    print(f"\nWritten to {OUTPUT}")


if __name__ == "__main__":
    main()

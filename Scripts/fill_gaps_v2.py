#!/usr/bin/env python3
"""Supplementary generation to fill remaining catalog gaps — round 2."""
import subprocess, sys, os

SCRIPTS = os.path.dirname(os.path.abspath(__file__))
CATALOG = os.path.join(SCRIPTS, "recipe_ingredient_orchestrator/output/ingredient_catalog.json")

BATCHES = [
    # ── Protein: Beef cuts ──
    {
        "prompt": (
            "Generate Protein category beef cuts. Each is a SEPARATE catalog entry "
            "with base_ingredient='beef'. MUST include ALL of these as individual entries: "
            "Filet Mignon (aliases: Beef Tenderloin Steak, Tenderloin), "
            "NY Strip Steak (aliases: New York Strip, Strip Steak), "
            "Flank Steak (aliases: London Broil), "
            "Skirt Steak (aliases: Fajita Meat), "
            "Beef Brisket (aliases: Brisket, Smoked Brisket), "
            "Chuck Roast (aliases: Pot Roast, Beef Chuck), "
            "Tri-Tip (aliases: Bottom Sirloin, Triangle Roast), "
            "T-Bone Steak (aliases: Porterhouse). "
            "Each must have form facets (whole, sliced etc) and preservation facets (fresh, frozen)."
        ),
        "count": 8,
    },
    # ── Protein: Pork, Sausage, Deli ──
    {
        "prompt": (
            "Generate Protein category entries. MUST include ALL of these as separate entries: "
            "Pork Shoulder (base_ingredient=pork, aliases: Pork Butt, Boston Butt), "
            "Baby Back Ribs (base_ingredient=pork, aliases: Pork Ribs, Loin Back Ribs), "
            "Spare Ribs (base_ingredient=pork, aliases: St. Louis Ribs, Pork Spare Ribs), "
            "Chorizo (aliases: Spanish Chorizo, Mexican Chorizo), "
            "Bratwurst (aliases: Brat, German Sausage), "
            "Andouille Sausage (aliases: Cajun Sausage, Smoked Andouille), "
            "Kielbasa (aliases: Polish Sausage, Smoked Kielbasa), "
            "Prosciutto (aliases: Italian Ham, Parma Ham), "
            "Pepperoni (aliases: Pizza Pepperoni), "
            "Salami (aliases: Italian Salami, Genoa Salami). "
            "Each with appropriate form and preservation facets."
        ),
        "count": 10,
    },
    # ── Protein: Lamb, Poultry, Other ──
    {
        "prompt": (
            "Generate Protein category entries. MUST include ALL as separate entries: "
            "Ground Lamb (base_ingredient=lamb, aliases: Minced Lamb, Lamb Mince), "
            "Lamb Leg (base_ingredient=lamb, aliases: Leg of Lamb, Lamb Roast), "
            "Lamb Shank (base_ingredient=lamb, aliases: Braised Lamb Shank), "
            "Chicken Drumstick (base_ingredient=chicken, aliases: Chicken Leg, Drumstick), "
            "Whole Turkey (base_ingredient=turkey, aliases: Roasting Turkey, Holiday Turkey), "
            "Cornish Hen (aliases: Game Hen, Rock Cornish Hen), "
            "Venison (aliases: Deer Meat, Game Meat), "
            "Bison (aliases: Buffalo Meat, Bison Steak). "
            "Each with form and preservation facets."
        ),
        "count": 8,
    },
    # ── Protein: Fish ──
    {
        "prompt": (
            "Generate Protein category fish entries. Each SEPARATE entry: "
            "Halibut (aliases: Pacific Halibut, Halibut Fillet), "
            "Tilapia (aliases: Tilapia Fillet), "
            "Sea Bass (aliases: Chilean Sea Bass, Branzino), "
            "Mahi-Mahi (aliases: Dolphinfish, Dorado), "
            "Swordfish (aliases: Swordfish Steak), "
            "Rainbow Trout (aliases: Trout, Steelhead Trout), "
            "Red Snapper (aliases: Snapper, Snapper Fillet), "
            "Catfish (aliases: Catfish Fillet, Channel Catfish), "
            "Sardines (aliases: Canned Sardines, Pilchards), "
            "Smoked Salmon (aliases: Lox, Nova, Gravlax). "
            "Each with form and preservation facets."
        ),
        "count": 10,
    },
    # ── Protein: Shellfish ──
    {
        "prompt": (
            "Generate Protein category shellfish entries. Each SEPARATE entry: "
            "Clams (aliases: Littleneck Clams, Manila Clams), "
            "Oysters (aliases: Fresh Oysters, Shucked Oysters), "
            "Calamari (aliases: Squid, Squid Rings), "
            "Octopus (aliases: Pulpo, Grilled Octopus), "
            "Crawfish (aliases: Crayfish, Crawdads). "
            "Each with form and preservation facets."
        ),
        "count": 5,
    },
    # ── Produce: Fruits ──
    {
        "prompt": (
            "Generate Produce category fruit entries. Each SEPARATE entry: "
            "Pineapple (aliases: Fresh Pineapple, Ananas), "
            "Watermelon (aliases: Fresh Watermelon), "
            "Cantaloupe (aliases: Muskmelon, Rock Melon), "
            "Honeydew (aliases: Honeydew Melon), "
            "Grapes (variant=red/green/black, aliases: Table Grapes), "
            "Raspberries (aliases: Fresh Raspberries), "
            "Blackberries (aliases: Fresh Blackberries), "
            "Peach (aliases: Fresh Peach, Nectarine), "
            "Plum (aliases: Fresh Plum, Prune Plum), "
            "Cherries (aliases: Sweet Cherries, Bing Cherries), "
            "Kiwi (aliases: Kiwifruit, Chinese Gooseberry), "
            "Pomegranate (aliases: Pomegranate Seeds), "
            "Cranberries (aliases: Fresh Cranberries), "
            "Figs (aliases: Fresh Figs, Dried Figs), "
            "Apricot (aliases: Fresh Apricot), "
            "Papaya (aliases: Pawpaw), "
            "Coconut (aliases: Fresh Coconut, Coconut Meat). "
            "Each with appropriate form and preservation facets."
        ),
        "count": 17,
    },
    # ── Produce: Vegetables ──
    {
        "prompt": (
            "Generate Produce category vegetable entries. Each SEPARATE entry: "
            "Brussels Sprouts (aliases: Baby Cabbages), "
            "Bok Choy (aliases: Pak Choi, Chinese Cabbage), "
            "Fennel (aliases: Fennel Bulb, Finocchio), "
            "Leek (aliases: Leeks), "
            "Radish (aliases: Red Radish, Daikon), "
            "Turnip (aliases: White Turnip), "
            "Parsnip (aliases: White Carrot), "
            "Artichoke (aliases: Globe Artichoke, Fresh Artichoke), "
            "Arugula (aliases: Rocket, Roquette), "
            "Swiss Chard (aliases: Rainbow Chard, Silverbeet), "
            "Watercress (aliases: Water Cress), "
            "Endive (aliases: Belgian Endive, Chicory), "
            "Okra (aliases: Lady Fingers, Gumbo). "
            "Each with form and preservation facets."
        ),
        "count": 13,
    },
    # ── Produce: Peppers & Herbs ──
    {
        "prompt": (
            "Generate Produce entries. Each SEPARATE entry: "
            "Serrano Pepper (aliases: Serrano Chile, Serrano), "
            "Habanero Pepper (aliases: Habanero Chile, Habanero), "
            "Poblano Pepper (aliases: Poblano Chile, Ancho Chile), "
            "Thai Chili (aliases: Bird's Eye Chili, Thai Bird Pepper), "
            "Chives (aliases: Fresh Chives), "
            "Sage (aliases: Fresh Sage, Garden Sage), "
            "Tarragon (aliases: French Tarragon), "
            "Lemongrass (aliases: Lemon Grass, Citronella Grass), "
            "Plantain (aliases: Cooking Banana, Green Plantain). "
            "Each with appropriate facets."
        ),
        "count": 9,
    },
    # ── Dairy ──
    {
        "prompt": (
            "Generate Dairy category entries. Each SEPARATE entry with base_ingredient='cheese': "
            "Blue Cheese (aliases: Bleu Cheese, Gorgonzola, Roquefort), "
            "Gruyere (aliases: Gruyère, Swiss Gruyere), "
            "Provolone (aliases: Provolone Cheese, Italian Provolone), "
            "Pepper Jack (aliases: Pepper Jack Cheese, Monterey Jack with Peppers), "
            "Monterey Jack (aliases: Jack Cheese, Monterey), "
            "Evaporated Milk (no base_ingredient, aliases: Canned Evaporated Milk). "
            "Cheeses must have base_ingredient='cheese'."
        ),
        "count": 6,
    },
    # ── Condiments ──
    {
        "prompt": (
            "Generate Condiments & Sauces entries. Each SEPARATE entry: "
            "Teriyaki Sauce (aliases: Japanese Teriyaki, Teriyaki Glaze), "
            "Gochujang (aliases: Korean Chili Paste, Red Pepper Paste), "
            "Harissa (aliases: Harissa Paste, North African Chili Paste), "
            "Red Curry Paste (base_ingredient=curry-paste, aliases: Thai Red Curry Paste), "
            "Green Curry Paste (base_ingredient=curry-paste, aliases: Thai Green Curry Paste), "
            "Mirin (aliases: Rice Wine, Sweet Rice Wine), "
            "Cooking Wine (aliases: Dry White Wine, Sherry for Cooking), "
            "Sriracha (aliases: Sriracha Hot Sauce, Rooster Sauce), "
            "Balsamic Glaze (aliases: Balsamic Reduction, Balsamic Vinegar Glaze), "
            "Dijon Mustard (aliases: French Mustard, Grey Poupon). "
            "Each with appropriate facets."
        ),
        "count": 10,
    },
    # ── Spices ──
    {
        "prompt": (
            "Generate Spices & Herbs entries. Each SEPARATE entry: "
            "Smoked Paprika (aliases: Pimentón, Spanish Paprika), "
            "White Pepper (aliases: Ground White Pepper), "
            "Star Anise (aliases: Chinese Star Anise, Anise Star), "
            "Fennel Seeds (aliases: Fennel Seed, Sweet Fennel), "
            "Mustard Seeds (aliases: Yellow Mustard Seeds, Brown Mustard Seeds), "
            "Za'atar (aliases: Zaatar, Middle Eastern Spice Blend), "
            "Celery Salt (aliases: Celery Seed Salt), "
            "Chinese Five Spice (aliases: Five Spice Powder, 5-Spice), "
            "Ground Coriander (aliases: Coriander Powder, Coriander Seed), "
            "Sumac (aliases: Ground Sumac, Sumac Spice). "
            "Each with appropriate facets."
        ),
        "count": 10,
    },
]

def run():
    for i, batch in enumerate(BATCHES, 1):
        prompt = batch["prompt"]
        count = batch["count"]
        print(f"\n[{i}/{len(BATCHES)}] {prompt[:70]}...")
        cmd = [
            sys.executable, "-m", "recipe_ingredient_orchestrator", "generate",
            "--count", str(count),
            "--seed-catalog", CATALOG,
            "--prompt", prompt,
        ]
        result = subprocess.run(cmd, cwd=SCRIPTS, capture_output=True, text=True)
        if result.stdout:
            for line in result.stdout.strip().split("\n"):
                if line.strip():
                    print(f"  {line.strip()}")
        if result.stderr:
            for line in result.stderr.strip().split("\n"):
                if line.strip():
                    print(f"  {line.strip()}")
        if result.returncode != 0:
            print(f"  *** BATCH FAILED (exit {result.returncode}) ***")
    print("\nAll batches complete!")

if __name__ == "__main__":
    run()

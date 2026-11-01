"""Fetch all fielding and advanced stats from npbbasement.com (2020-2026, 1g and 2g)
and save them as JSON in data/basement/
"""
import urllib.request
import json
import re
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASEMENT_DIR = ROOT / "data" / "basement"
BASEMENT_DIR.mkdir(parents=True, exist_ok=True)

URLS = {
    "2020_1g": "https://npbbasement.com/assets/2020_1g-CqlvTRt2.js",
    "2021_1g": "https://npbbasement.com/assets/2021_1g-fTyLekEh.js",
    "2021_2g": "https://npbbasement.com/assets/2021_2g-CGnXFqkz.js",
    "2022_1g": "https://npbbasement.com/assets/2022_1g-C6zcmHX3.js",
    "2022_2g": "https://npbbasement.com/assets/2022_2g-BvxsYJZP.js",
    "2023_1g": "https://npbbasement.com/assets/2023_1g-CWVMm00F.js",
    "2023_2g": "https://npbbasement.com/assets/2023_2g-BYKqcJue.js",
    "2024_1g": "https://npbbasement.com/assets/2024_1g-CT611ZN8.js",
    "2024_2g": "https://npbbasement.com/assets/2024_2g-CYbcYD37.js",
    "2025_1g": "https://npbbasement.com/assets/2025_1g-IWrJ-Vkl.js",
    "2025_2g": "https://npbbasement.com/assets/2025_2g-BAD9NnSe.js",
    "2026_1g": "https://npbbasement.com/assets/2026_1g-jYJ3JAnu.js",
    "2026_2g": "https://npbbasement.com/assets/2026_2g-CyfwpUXJ.js",
}

def fetch_and_save(key: str, url: str):
    out_file = BASEMENT_DIR / f"{key}.json"
    if out_file.exists():
        print(f"Already exists: {out_file}")
        return
    print(f"Fetching {key} from {url}...")
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'})
    content = urllib.request.urlopen(req).read().decode('utf-8')
    
    idx1 = content.find("`")
    idx2 = content.rfind("`")
    if idx1 == -1 or idx2 == -1:
        raise ValueError(f"Could not find backticks in {key}")
    
    json_str = content[idx1+1:idx2].replace('\\`', '`')
    data = json.loads(json_str)
    
    with out_file.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    print(f"Saved {len(data)} players to {out_file}")

def main():
    for key, url in URLS.items():
        fetch_and_save(key, url)
        time.sleep(0.5)
    print("All basement files downloaded successfully.")

if __name__ == "__main__":
    main()

"""Regenerate Where2Go/Core/Sources.lua's dungeon/raid item-pool data from
the Battle.net Game Data API Journal endpoints for the current season.

Usage:
    BLIZZARD_CLIENT_ID=... BLIZZARD_CLIENT_SECRET=... python tools/data-prep/generate_sources.py

Never writes Where2Go/Core/Sources.lua directly -- it stages output at
tools/data-prep/scratch/Sources.lua.new and prints a diff for review.
See docs/SEASON_CHECKLIST.md for the full season-changeover procedure.
"""

import base64
import difflib
import json
import os
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
SCRATCH = os.path.join(HERE, "scratch")
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SOURCES_LUA_PATH = os.path.join(REPO_ROOT, "Where2Go", "Core", "Sources.lua")

REGION_HOST = "https://us.api.blizzard.com"

# Update this each season -- see docs/SEASON_CHECKLIST.md step 1. The
# Battle.net API has no "current season" endpoint, so these instance IDs
# must be looked up by hand (e.g. wowhead/wiki) and filled in here.
SEASON_INSTANCES = {
    "dungeons": [1322, 1311, 1304, 1309, 1313, 1041, 1202, 1030],
    "raids": [1317, 1320],
}


def get_token():
    client_id = os.environ["BLIZZARD_CLIENT_ID"]
    client_secret = os.environ["BLIZZARD_CLIENT_SECRET"]
    auth = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
    req = urllib.request.Request(
        "https://oauth.battle.net/token",
        data=b"grant_type=client_credentials",
        headers={"Authorization": f"Basic {auth}"},
        method="POST",
    )
    with urllib.request.urlopen(req) as resp:
        data = json.load(resp)
    os.makedirs(SCRATCH, exist_ok=True)
    with open(os.path.join(SCRATCH, "token.json"), "w", encoding="utf-8") as f:
        json.dump(data, f)
    return data["access_token"]


def api_get(token, path, namespace="static-us", locale="en_US"):
    url = f"{REGION_HOST}{path}?namespace={namespace}&locale={locale}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)


def fetch_instance(token, instance_id):
    instance = api_get(token, f"/data/wow/journal-instance/{instance_id}")
    encounters = []
    for enc_ref in instance.get("encounters", []):
        enc_id = enc_ref["id"]
        detail = api_get(token, f"/data/wow/journal-encounter/{enc_id}")
        item_ids = [item["item"]["id"] for item in detail.get("items", [])]
        encounters.append({
            "bossId": enc_id,
            "name": detail["name"],
            "itemIds": item_ids,
        })
    return {"instanceId": instance_id, "name": instance["name"], "encounters": encounters}


def check_structural_warnings(label, instances):
    for instance in instances:
        seen_boss_ids = set()
        for encounter in instance["encounters"]:
            if not encounter["itemIds"]:
                print(
                    f"WARNING: {label} '{instance['name']}' encounter "
                    f"'{encounter['name']}' (bossId {encounter['bossId']}) has no items"
                )
            if encounter["bossId"] in seen_boss_ids:
                print(
                    f"WARNING: {label} '{instance['name']}' has duplicate "
                    f"bossId {encounter['bossId']}"
                )
            seen_boss_ids.add(encounter["bossId"])

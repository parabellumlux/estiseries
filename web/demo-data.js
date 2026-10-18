// SkinSeries demo data — mirrors assets/demo/demo_data.json exactly.
// Loaded with a plain script tag; exposes window.DEMO_DATA for app.js.
window.DEMO_DATA = {
  "clients": [
    {
      "id": "maya",
      "name": "Maya R.",
      "plan": {
        "focus": [
          {
            "concern": "moisture",
            "note": "Hydration Boost Serum morning and night; lukewarm water only when cleansing."
          },
          {
            "concern": "redness",
            "note": "Gentle hands, no scrubs between sessions; note any flare-ups in the week before each visit."
          },
          {
            "concern": "radiance",
            "note": "One gentle enzyme polish at home per week, starting after session 2."
          }
        ],
        "productIds": ["p2", "p3", "p4"],
        "regimen": {
          "am": "Gentle Renewal Cleanser → Hydration Boost Serum → Calm Moisture Cream → Mineral SPF 50",
          "pm": "Gentle Renewal Cleanser → Hydration Boost Serum → Calm Moisture Cream"
        },
        "seriesName": "Calm + Hydrate Renewal Series",
        "sessions": 6
      },
      "scans": [
        {
          "date": "2026-07-13",
          "id": "scan-baseline",
          "label": "Baseline",
          "overall": 61,
          "scores": {
            "acne": 55,
            "ageSpot": 71,
            "darkCircle": 54,
            "droopyLowerEyelid": 80,
            "droopyUpperEyelid": 78,
            "eyeBag": 59,
            "firmness": 64,
            "moisture": 42,
            "oiliness": 66,
            "pore": 60,
            "radiance": 52,
            "redness": 58,
            "tearTrough": 69,
            "texture": 57,
            "wrinkle": 63
          },
          "sessionNumber": 1,
          "skinAge": 47,
          "skinType": "Combination",
          "stage": "baseline"
        },
        {
          "date": "2026-08-24",
          "id": "scan-session3",
          "label": "Session 3",
          "overall": 68,
          "scores": {
            "acne": 63,
            "ageSpot": 70,
            "darkCircle": 57,
            "droopyLowerEyelid": 79,
            "droopyUpperEyelid": 78,
            "eyeBag": 58,
            "firmness": 66,
            "moisture": 54,
            "oiliness": 68,
            "pore": 62,
            "radiance": 61,
            "redness": 66,
            "tearTrough": 68,
            "texture": 63,
            "wrinkle": 63
          },
          "sessionNumber": 3,
          "skinAge": 45,
          "skinType": "Combination",
          "stage": "session3"
        },
        {
          "date": "2026-10-05",
          "id": "scan-session6",
          "label": "Session 6",
          "overall": 74,
          "scores": {
            "acne": 71,
            "ageSpot": 69,
            "darkCircle": 62,
            "droopyLowerEyelid": 79,
            "droopyUpperEyelid": 77,
            "eyeBag": 60,
            "firmness": 69,
            "moisture": 63,
            "oiliness": 70,
            "pore": 66,
            "radiance": 70,
            "redness": 74,
            "tearTrough": 67,
            "texture": 69,
            "wrinkle": 65
          },
          "sessionNumber": 6,
          "skinAge": 44,
          "skinType": "Combination",
          "stage": "session6"
        }
      ],
      "seriesName": "Calm + Hydrate Renewal Series",
      "seriesTemplateId": "t1",
      "totalSessions": 6
    }
  ],
  "concerns": [
    { "key": "wrinkle", "label": "Wrinkles" },
    { "key": "pore", "label": "Pores" },
    { "key": "texture", "label": "Texture" },
    { "key": "acne", "label": "Acne" },
    { "key": "oiliness", "label": "Oiliness" },
    { "key": "radiance", "label": "Radiance" },
    { "key": "eyeBag", "label": "Eye bags" },
    { "key": "ageSpot", "label": "Age spots" },
    { "key": "darkCircle", "label": "Dark circles" },
    { "key": "droopyUpperEyelid", "label": "Droopy upper eyelids" },
    { "key": "droopyLowerEyelid", "label": "Droopy lower eyelids" },
    { "key": "firmness", "label": "Firmness" },
    { "key": "moisture", "label": "Moisture" },
    { "key": "redness", "label": "Redness" },
    { "key": "tearTrough", "label": "Tear trough" }
  ],
  "practice": {
    "accent": "#B0714F",
    "bookingUrl": "https://example.com/book/lunaglow",
    "id": "lunaglow",
    "name": "Luna Glow Skin Studio",
    "practitioner": "Ava Luna",
    "scanUrl": "https://scan.skinseries.app/s/lunaglow",
    "tagline": "Skin care, measured."
  },
  "products": [
    { "id": "p1", "name": "Gentle Renewal Cleanser", "price": 38 },
    { "id": "p2", "name": "Hydration Boost Serum", "price": 64 },
    { "id": "p3", "name": "Calm Moisture Cream", "price": 52 },
    { "id": "p4", "name": "Mineral SPF 50", "price": 34 }
  ],
  "seriesTemplates": [
    {
      "defaultFocus": ["moisture", "redness", "radiance"],
      "description": "A six-session series for dry, reactive skin: hydration first, then calm, then glow.",
      "id": "t1",
      "name": "Calm + Hydrate Renewal Series",
      "sessions": 6
    },
    {
      "defaultFocus": ["acne", "oiliness", "texture"],
      "description": "A four-session series focused on breakouts, oil balance, and texture.",
      "id": "t2",
      "name": "Clarifying Series",
      "sessions": 4
    },
    {
      "defaultFocus": ["radiance", "texture", "darkCircle"],
      "description": "A three-session refresh for dull skin ahead of an event or season change.",
      "id": "t3",
      "name": "Glow Facial Series",
      "sessions": 3
    },
    {
      "defaultFocus": [],
      "description": "A series built from scratch around this client's scan.",
      "id": "t4",
      "name": "Custom Series",
      "sessions": 6
    }
  ]
};

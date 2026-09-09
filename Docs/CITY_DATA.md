# How real-city boards are generated

`RichmanCityData` turns a city name a player types (e.g. "New York") into a real `RichmanCore.Board` — 40 tiles shaped by `BoardTemplate.classicSlotOrder` (see [`ARCHITECTURE.md`](ARCHITECTURE.md)), but named after that city's actual streets, transit stations, and landmarks.

## Pipeline

1. **Geocode** (`NominatimGeocoder`) — the city name is sent to [OpenStreetMap Nominatim](https://nominatim.org/), a free, keyless geocoder, which returns a display name and a bounding box.
2. **Query** (`OverpassClient`) — that bounding box is sent to the free [Overpass API](https://overpass-api.de/) for:
   - named major roads (`highway` = `motorway`/`trunk`/`primary`/`secondary`) — deliberately excludes `residential`, since a handful of named avenues reads better as board tiles than an arbitrary side street, and residential ways alone can be 10x the volume of everything else combined;
   - railway/subway stations (`railway=station`, `station=subway`);
   - landmarks (`tourism=attraction`) and airports (`aeroway=aerodrome`).

   Each block has its own numeric cap (roads 300, stations 120, landmarks 60). OSM splits roads into a new "way" at every intersection, so a single named avenue in a big city can appear as hundreds of segments; uncapped, a city like New York returns 50,000+ elements and tens of megabytes for a query that only needs ~28 distinct names. Capping keeps the fetch fast on a phone and keeps this app a reasonable citizen of a shared, free public API.

3. **Rank & select** (`BoardLayoutBuilder`) —
   - Every candidate road/station/landmark is deduplicated by name, then sorted by **polar angle around the city's center** (an arbitrary start angle, increasing counter-clockwise) rather than by distance. Walking the board's fixed slot order while popping from these angle-sorted lists produces a sequence that hugs the outer boundary of the selected points — a cheap stand-in for real road-network routing, and what makes the board's shape actually trace the city (see "Board shape" below).
   - Roads fill the 22 property slots, stations the 4 transit slots, landmarks/airports the 2 utility slots, all in that angle order.
   - If a city doesn't have enough tagged data (a small town, sparse OSM coverage), the remaining slots are padded with generic names (`Local Road N`, etc.) so the board is always fully playable.
4. **Price/rent** — every property/transit/utility tile gets its price and rent table from `BoardTemplate.propertyDetails`/`transitDetails`/`utilityDetails` — the same formula `StandardBoard` uses, keyed only by the tile's position in the classic slot order. A city board is never mechanically different from the generic one, only re-skinned. Price now correlates with *how far along the geographic loop* a tile falls, not distance from the center specifically — a deliberate trade discussed below.

## Board shape

Every tile also gets a `RichmanCore.TileMapPosition` (normalized `0...1`, aspect-ratio preserved) instead of always sitting on a square perimeter:

1. Real (lat, lon) is recorded for every non-padded road/station/landmark tile as it's assigned to a slot.
2. Those coordinates are fit into a `0...1` box, preserving the city's real aspect ratio (a tall city stays tall, not stretched square).
3. A lightweight pairwise-repulsion pass (`decluttered(_:)`) nudges any tiles closer together than one tile-chip-width apart — real geography can put several tiles right on top of each other (dense downtown blocks vs. a sprawling suburb), which a fixed-size chip can't render legibly. This is a local nudge, not a reshape; the overall path still traces the real geography.
4. Every remaining tile (padded properties/stations/utilities, and every generic tile — Go, Jail, Chance, Tax, etc.) gets a position by linearly interpolating between the nearest real-positioned tiles before and after it in board order, so the path has no gaps.

`RichmanGameUI`'s `BoardView` renders any board where every tile has a `mapPosition` as a winding path (tiles strung along a line in board order) instead of the classic square — see `Packages/RichmanGameUI/Sources/RichmanGameUI/BoardView.swift`. `StandardBoard` never sets `mapPosition`, so the generic (no-city) board is unaffected and keeps the classic square.

## Known simplifications

- The path is an angle-sorted approximation of the region's outline, not real road-network routing — it won't follow actual streets turn-by-turn, just the overall shape of where they are.
- Color groups are still assigned by position in the angle-sorted sequence, not true geographic clustering (e.g. "these 3 roads are all in the same neighborhood"). A real neighborhood-clustering pass (e.g. using OSM `place`/`suburb` boundaries) would be a nice future improvement, isolated entirely to `BoardLayoutBuilder`.
- No terrain/landmass art — just the path line and tile chips (placeholder-tier, like everything else `RichmanAssetsKit` hasn't been given real art for yet).

## Offline / bundled cities

`BundledCityDataProvider` ships pre-fetched `CityBoardLayout` JSON (in `Packages/RichmanCityData/Sources/RichmanCityData/Resources/BundledCities/`) for a couple of cities, so the game has an instant, network-free demo path and a fallback if a live fetch fails. Regenerate or add one with the bundled dev tool:

```bash
cd Packages/RichmanCityData
swift run city-data-generator "New York" Sources/RichmanCityData/Resources/BundledCities/new_york.json
```

`RichmanPersistence` separately caches any city a player actually looks up, live or bundled, so repeat play never re-hits the network.

## Rate limits & etiquette

Both Nominatim and Overpass are free, shared, community-run services with usage policies (a descriptive `User-Agent`, roughly 1 request/second, no bulk scraping). Because results are cached after first fetch, normal play only ever makes one geocode + one Overpass call per *new* city a player tries — well within those limits. Don't loop city fetches in a script without adding delays between requests (see the generator tool above for a single-city example).

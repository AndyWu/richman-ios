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

## Board shape: a Tube-map-style schematic, not literal geography

Every tile also gets a `RichmanCore.TileMapPosition` (normalized `0...1`) instead of always sitting on a square perimeter — but rather than plotting literal (lat, lon), positions are schematized the way a transit diagram (the London Underground map) is: straight spokes at clean compass angles, not a geographically accurate trace. Two earlier approaches were tried and replaced:

- **Literal (lat, lon), aspect-preserved** — tiles landed at their real position. Looked geographically faithful, but real coordinates routinely put several tiles on top of each other (dense downtown blocks vs. a sprawling suburb), and the connecting line crossed itself in messy, hard-to-read tangles.
- **Literal positions + pairwise-repulsion decluttering** — nudged overlapping tiles apart after the fact. Fixed the worst overlaps but the path still wasn't straight or clean, and self-crossings could still occur.

The current approach (`snappedToCompassDirections` in `BoardLayoutBuilder`) instead:

1. Computes the centroid of every tile that got a real coordinate, and expresses each one as (bearing, distance) from *that* centroid — not the city's geocoded query center, which is often skewed to one side of where the selected roads actually cluster and would otherwise cram most tiles into one or two directions.
2. Splits tiles into 8 buckets **by quantile** (equal tile count per bucket) rather than equal-angle wedges, then renders each bucket at one of the 8 fixed compass angles (0°, 45°, 90°, ... 315°). Quantile splitting is what keeps every direction similarly populated even when the real bearings are skewed — a fixed 45°-wedge split would leave that skew intact.
3. Within a bucket, tiles get strictly distinct radii along that ray (ordered by real distance from center, closer tiles nearer the hub), spread across a fixed radius range — fixed regardless of bucket size, so the diagram's overall size doesn't balloon just because one direction happened to collect more tiles.

Because bearing increases monotonically around the board's loop by construction (tiles are assigned to slots in angle-sorted order to begin with), this is a "star-shaped" polar curve — one where the radius can vary in any way along each ray without ever making the loop cross itself. That's what guarantees no overlapping routes structurally, rather than needing to detect and fix overlaps after the fact.

Every remaining tile (padded properties/stations/utilities, and every generic tile — Go, Jail, Chance, Tax, etc.) gets a placeholder bearing/distance by linearly interpolating between the nearest real-positioned tiles before and after it in board order (handling the one point where bearing wraps back through 0°/360°), so the path has no gaps, then goes through the same bucket-and-snap step as everything else.

`RichmanGameUI`'s `BoardView` renders any board where every tile has a `mapPosition` as this spoked path instead of the classic square — see `Packages/RichmanGameUI/Sources/RichmanGameUI/BoardView.swift`. `StandardBoard` never sets `mapPosition`, so the generic (no-city) board is unaffected and keeps the classic square.

## Known simplifications

- The board's overall shape is a schematic 8-way star, not a trace of the city's actual outline — a deliberate trade for a clean, non-overlapping diagram (the explicit ask that motivated this design), the same trade the real Tube map makes for legibility over geographic accuracy.
- Color groups are still assigned by position in the angle-sorted slot sequence, not true geographic clustering (e.g. "these 3 roads are all in the same neighborhood"). A real neighborhood-clustering pass (e.g. using OSM `place`/`suburb` boundaries) would be a nice future improvement, isolated entirely to `BoardLayoutBuilder`.
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

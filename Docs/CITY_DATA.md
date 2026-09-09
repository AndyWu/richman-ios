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

## Board shape: real topology, drawn like a Tube map

Every tile also gets a `RichmanCore.TileMapPosition` (normalized `0...1`, real aspect ratio preserved) instead of always sitting on a square perimeter — `BoardLayoutBuilder` is responsible for *where things really are*, and `RichmanGameUI.BoardView` is responsible for *drawing that legibly*, kept as two separate concerns after a few iterations landed on the wrong side of that split. Three approaches were tried:

1. **Literal (lat, lon), aspect-preserved** — tiles at their real position, connected with a plain line. Real coordinates routinely put several tiles on top of each other (dense downtown blocks vs. a sprawling suburb), and the connecting line crossed itself in messy tangles.
2. **8-direction star** — every tile's bearing snapped to the nearest of 8 compass directions from a shared center, all radiating from one hub. Solved the overlap problem completely (a curve with monotonically-increasing bearing can't self-intersect), but looked like a generic 8-spoke asterisk, not the city — real position was discarded almost entirely.
3. **Current: real positions + declutter (`BoardLayoutBuilder`) + octilinear bend-insertion at render time (`BoardView`)** — the one actually in use.

`BoardLayoutBuilder` fits every tile's real (lat, lon) into `0...1` (`normalizedPositions`), interpolates a position for every tile that didn't get a real coordinate (`interpolatedPositions`), then runs a pairwise-repulsion pass (`decluttered`) that nudges any two tiles closer than one tile-width apart away from each other — real geography can still put several tiles nearly on top of each other, and a fixed-size chip can't render that legibly. That's it; positions stay real and organic, not snapped to any grid or direction.

The Tube-map look — every drawn segment horizontal, vertical, or 45° — is purely a `BoardView` rendering concern (`RouteGeometry.octilinearWaypoints`): for each pair of adjacent tiles, if their direct line isn't already one of those angles, insert one bend point (a diagonal run covering however much of the gap is shared between both axes, then a straight run covering the rest). Any two points can always be connected this way with exactly one bend, so every segment actually drawn is clean while the tiles themselves stay at their real, city-shaped positions.

Each tile's outgoing leg (the road from that tile to the next one in board order) is drawn thick and in its own color (`RouteGeometry.routeColor`, stepped by the golden angle so consecutive tiles — the ones actually next to each other on screen — never land on similar hues even though there are 40 of them), like a network of distinctly-colored transit lines rather than one long path. Tile chips sit opaquely on top as "stops." A leg long enough to otherwise look like bare, empty track (`RouteGeometry.intermediateStops`) gets a few small evenly-spaced dots in the same color along its length — visual only, not real board tiles, just keeping a long real-world gap between two stops from reading as broken.

## Known simplifications

- The path follows the *order* real roads/stations/landmarks were selected in (see "Rank & select" above), not real road-network connectivity — it won't retrace an actual street turn-by-turn, just approximate the city's overall shape.
- The declutter pass is a local nudge (pairwise repulsion), not a full layout optimizer — very dense clusters of real places can still end up visually tight, just no longer exactly overlapping.
- Color groups (for game pricing/rent purposes) are still assigned by position in the angle-sorted slot sequence, not true geographic clustering (e.g. "these 3 roads are all in the same neighborhood"). A real neighborhood-clustering pass (e.g. using OSM `place`/`suburb` boundaries) would be a nice future improvement, isolated entirely to `BoardLayoutBuilder`. (This is separate from the per-tile *route* colors above, which are purely visual.)
- No terrain/landmass art — just the route lines, stop dots, and tile chips (placeholder-tier, like everything else `RichmanAssetsKit` hasn't been given real art for yet).

## Offline / bundled cities

`BundledCityDataProvider` ships pre-fetched `CityBoardLayout` JSON (in `Packages/RichmanCityData/Sources/RichmanCityData/Resources/BundledCities/`) for a couple of cities, so the game has an instant, network-free demo path and a fallback if a live fetch fails. Regenerate or add one with the bundled dev tool:

```bash
cd Packages/RichmanCityData
swift run city-data-generator "New York" Sources/RichmanCityData/Resources/BundledCities/new_york.json
```

`RichmanPersistence` separately caches any city a player actually looks up, live or bundled, so repeat play never re-hits the network.

## Rate limits & etiquette

Both Nominatim and Overpass are free, shared, community-run services with usage policies (a descriptive `User-Agent`, roughly 1 request/second, no bulk scraping). Because results are cached after first fetch, normal play only ever makes one geocode + one Overpass call per *new* city a player tries — well within those limits. Don't loop city fetches in a script without adding delays between requests (see the generator tool above for a single-city example).

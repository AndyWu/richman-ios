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
   - Roads are deduplicated by name and sorted **farthest-from-center first**; the 22 property slots are filled in that order, so tiles near Go are the cheapest (outskirts) and tiles in the last color group are the priciest (city center) — the classic Monopoly cheap-to-expensive ramp, driven by real geography instead of an arbitrary list.
   - Stations are deduplicated and sorted **closest-to-center first** (major hubs tend to be central) to fill the 4 transit tiles.
   - Landmarks/airports fill the 2 utility tiles, closest-to-center first.
   - If a city doesn't have enough tagged data (a small town, sparse OSM coverage), the remaining slots are padded with generic names (`Local Road N`, etc.) so the board is always fully playable.
4. **Price/rent** — every property/transit/utility tile gets its price and rent table from `BoardTemplate.propertyDetails`/`transitDetails`/`utilityDetails` — the same formula `StandardBoard` uses, keyed only by the tile's position in the classic slot order. A city board is never mechanically different from the generic one, only re-skinned.

## Known simplification

Properties are grouped into color groups by their position in the farthest-to-closest ranking, not by real geographic clustering (e.g. "these 3 roads are all in the same neighborhood"). This is a reasonable approximation — roads at similar distance from the center tend to be roughly contemporaneous — but a true neighborhood-clustering pass (e.g. using OSM `place`/`suburb` boundaries) would be a nice future improvement, isolated entirely to `BoardLayoutBuilder`.

## Offline / bundled cities

`BundledCityDataProvider` ships pre-fetched `CityBoardLayout` JSON (in `Packages/RichmanCityData/Sources/RichmanCityData/Resources/BundledCities/`) for a couple of cities, so the game has an instant, network-free demo path and a fallback if a live fetch fails. Regenerate or add one with the bundled dev tool:

```bash
cd Packages/RichmanCityData
swift run city-data-generator "New York" Sources/RichmanCityData/Resources/BundledCities/new_york.json
```

`RichmanPersistence` separately caches any city a player actually looks up, live or bundled, so repeat play never re-hits the network.

## Rate limits & etiquette

Both Nominatim and Overpass are free, shared, community-run services with usage policies (a descriptive `User-Agent`, roughly 1 request/second, no bulk scraping). Because results are cached after first fetch, normal play only ever makes one geocode + one Overpass call per *new* city a player tries — well within those limits. Don't loop city fetches in a script without adding delays between requests (see the generator tool above for a single-city example).

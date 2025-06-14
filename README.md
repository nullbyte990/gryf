# Gryf

Aplikacja geoinformacyjna oparta na mapach wektorowych OpenMapTiles. Backend w Symfony, frontend z mapą MapLibre GL JS, kafelki wektorowe serwowane przez Martin z lokalnie wygenerowanych plików MBTiles.

## Stos technologiczny

| Usługa | Technologia | Port |
|--------|-------------|------|
| Frontend | HTML + MapLibre GL JS | `localhost:80` |
| Backend | PHP 8.4 / Symfony 8.0 | `backend.localhost:80` |
| Baza danych | PostgreSQL 14 + PostGIS 3.5 | `localhost:5432` |
| Kafelki wektorowe | Martin 1.4.0 | `localhost:3000` |
| Routing | Valhalla (OSM Polska) | `localhost:8002` |
| Geokoder | Photon 1.2.0 | `localhost:2322` |
| Cache | Valkey 8 (Redis-compatible) | `localhost:6379` |

## Wymagania

- Docker + Docker Compose
- `make`

## Uruchomienie

```bash
# Zbuduj obrazy
make build

# Uruchom wszystkie usługi
make up
```

Frontend dostępny pod `http://localhost`, backend pod `http://backend.localhost`.

## Kafelki wektorowe (mapy)

Kafelki generowane są lokalnie ze źródeł OpenStreetMap dla całej Polski i zapisywane jako `maps/poland.mbtiles`. Martin serwuje je automatycznie po uruchomieniu.

### Generowanie kafelków

Wymagane narzędzia (instalowane lokalnie, poza Dockerem):

```
tilemaker, wget, curl, unzip, python3,
osmium, sqlite3, ogr2ogr, gdal_contour,
gdalinfo, gdalbuildvrt, gdal_translate, eio
```

```bash
cd maps
bash maps.sh
```

Skrypt pobiera `poland-latest.osm.pbf` z Geofabrik (~1 GB), dane pomocnicze (linie brzegowe, Natural Earth), generuje warstwy konturów terenu (SRTM, interwał 20m) i uruchamia tilemaker. Wynik: `maps/poland.mbtiles`.

Po wygenerowaniu pliku wystarczy zrestartować usługę Martin:

```bash
docker compose restart martin
```

Kafelki dostępne pod `http://localhost:3000/poland/{z}/{x}/{y}`, katalog źródeł: `http://localhost:3000/catalog`.

## Geokoder Photon

Photon działa jako lokalny silnik geokodowania na `http://localhost:2322`. Backend ma domyślnie ustawiony adres wewnętrzny `PHOTON_URL=http://photon:2322`.

Kontener ma lokalny mechanizm podobny do obrazów z obsługą `REGION`: `PHOTON_REGION=PL` i `PHOTON_COUNTRY_CODES=PL` są domyślne, a entrypoint odrzuci inne regiony. Dzięki temu nie da się przypadkowo zainicjalizować Photona danymi świata ani Europy.

Przy pierwszym uruchomieniu pusty wolumen `photon_data` zostanie automatycznie zainicjalizowany z dumpa GraphHoppera dla Polski. Domyślny dump to `https://download1.graphhopper.com/public/europe/poland/photon-dump-poland-1.0-latest.jsonl.zst`; można go nadpisać zmienną `PHOTON_DUMP_URL`.

Pierwsze uruchomienie:

```bash
docker compose up -d photon
```

Entrypoint pobiera skompresowany dump do tymczasowego katalogu w wolumenie, rozpakowuje go przez `zstd` i importuje do tymczasowej bazy Photona. Dopiero po udanym imporcie przenosi gotowy katalog `photon_data` na właściwe miejsce i zapisuje marker `.gryf-import-complete`. Dzięki temu przerwany albo nieudany import nie zostawia pustej bazy, która blokowałaby kolejną próbę.

Po udanym imporcie kolejne uruchomienia pomijają import i startują serwer od razu. Jeśli import nie utworzy danych, kontener kończy się błędem, a `restart: on-failure` ponowi próbę.

Przy zmianie entrypointa lub obrazu Photona odbuduj usługę:

```bash
docker compose up -d --build --force-recreate photon
```

API wyszukiwania:

```bash
curl 'http://localhost:2322/api?q=Warszawa&limit=5'
curl 'http://localhost:2322/reverse?lon=21.0122&lat=52.2297'
```

## Komendy Makefile

```bash
make build          # Zbuduj obrazy Docker
make up             # Uruchom usługi (tryb tła)
make stop           # Zatrzymaj usługi
make down           # Zatrzymaj i usuń kontenery
make sh             # Wejdź do powłoki kontenera PHP
make logs           # Pokaż logi PHP
make install        # Zainstaluj zależności Composer
```

### Jakość kodu

```bash
make lint           # Sprawdź konfigurację Symfony
make phpstan        # Analiza statyczna PHPStan
make cs-check       # Sprawdź styl kodu (ECS)
make cs-fix         # Popraw styl kodu (ECS)
make rector-check   # Podgląd zmian Rector
make rector-fix     # Zastosuj zmiany Rector
make check          # Wszystkie sprawdzenia
make fix            # Wszystkie automatyczne poprawki
make qa             # Pełny zestaw QA
```

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

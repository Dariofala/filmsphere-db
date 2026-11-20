# 🎬 FilmSphere - Relational Database for a Film Streaming Platform

![MySQL](https://img.shields.io/badge/MySQL-8.0+-4479A1?logo=mysql&logoColor=white)
![SQL](https://img.shields.io/badge/language-SQL-orange)
![Status](https://img.shields.io/badge/status-academic%20project-lightgrey)

FilmSphere is the complete design and MySQL implementation of the database behind a fictional
**global film-streaming service**: catalogue, formats, users, subscriptions, billing, viewing history,
and a worldwide **CDN** (Content Delivery Network) that streams content from the most suitable server.

Developed for the **Databases** course (*Basi di Dati*) of the BSc in Computer Engineering, academic year 2022/23.

---

## ✨ Highlights

- **Full design process**: conceptual E-R model → restructuring → volume table → redundancy analysis →
  logical design → functional dependencies & **BCNF** normalisation (see [`docs/`](docs/)).
- **25 tables** organised in four areas: *Content*, *Formats*, *Customers*, *Streaming*.
- **Business rules enforced in the database** with 15 triggers and 4 scheduled events, for example:
  - age and geographic restrictions of each subscription plan;
  - monthly streaming-hours quota, decreased at every viewing and reset every month;
  - content quality allowed by the plan (SD / HD / Full HD / 4K) and format availability per country;
  - IP address validation against the geographic area of the connection.
- **CDN simulation**: each connection is routed to the nearest server that is not overloaded;
  a scheduled event rebalances overloaded servers, and server status (*Good / Fair / Poor*) is updated automatically.
- **Per-user caching**: every week each user's cache is filled with unseen films of their favourite genre.
- **Data analytics**:
  1. top-10 rankings of the most watched films per CDN server and per subscription plan,
     with the best available format for each film;
  2. an automatic **rating algorithm** combining user votes (critics count 3×), awards won and the directors' track record.
- **Realistic sample data**: ~3,500 lines covering 30 films, 100 users, 500 connections, 400+ viewings and 500 ratings.

## 🗂️ Repository structure

```
filmsphere-db/
├── sql/
│   ├── 01_schema.sql            # database and tables
│   ├── 02_triggers_events.sql   # integrity constraints: triggers, events, helper functions
│   ├── 03_operations.sql        # main operations (stored procedures / functions)
│   ├── 04_analytics_ranking.sql # analytic 1: top-10 rankings
│   ├── 05_analytics_rating.sql  # analytic 2: film rating algorithm
│   ├── 06_seed_data.sql         # sample data (fictional)
│   └── 07_demo_calls.sql        # example calls of every operation
└── docs/
    ├── documentazione.pdf       # full project report (Italian)
    ├── er-non-ristrutturato.pdf # conceptual E-R diagram
    └── er-ristrutturato.pdf     # restructured E-R diagram
```

## 🧩 Data model

| Area | Main tables |
|------|-------------|
| **Content** | `Film`, `Regista`, `Regia`, `AttorePrincipale`, `Cast_`, `Premio`, `Lingua`, `Audio`, `Sottotitoli`, `Produzione` |
| **Formats** | `Formato`, `Rilascio`, `Disponibilita` |
| **Customers** | `Utente`, `Abbonamento`, `Iscrizione`, `Restrizione`, `Fattura`, `Cronologia`, `RatingPersonale` |
| **Streaming** | `ServerCDN`, `Connessione`, `Cache`, `Salvataggio`, `AreaGeografica` |

The full E-R diagrams are in [`docs/er-ristrutturato.pdf`](docs/er-ristrutturato.pdf).
Table and column names are in Italian, as in the original project.

## 🚀 Getting started

**Requirements:** MySQL **8.0 or later** (window functions and CTEs are used) and the `mysql` command-line client
or MySQL Workbench (the scripts use the `DELIMITER` command).

Run the scripts **in order**:

```bash
for f in sql/0*.sql; do
  echo "Running $f"
  mysql -u root -p < "$f"
done
```

Or one at a time: `mysql -u root -p < sql/01_schema.sql`, then `02`, `03`, … up to `07`.

The scheduled events (cache refresh, history cleanup, monthly hours reset, CDN rebalancing) only run if the
event scheduler is enabled:

```sql
SET GLOBAL event_scheduler = ON;
```

### Example queries

```sql
USE FilmSphere;

CALL FilmPiuVistiSettimana();                  -- top 10 films of the week
CALL RaccomandazioneContenuti("BIALUC001");    -- recommendations for a user
CALL RankFilmPerAbbonamento("Ultimate");       -- most watched films by plan
SELECT NumAreeDiverse("BIALUC001");            -- countries a user connected from this month
```

> The sample data is dated 2022, so queries that depend on the current date (e.g. "this week")
> return results only after inserting new, recent records.

## 🔧 Post-exam revision

The project was revised after the exam. The report in [`docs/`](docs/) describes the original submission;
the SQL code in this repository includes the following fixes:

- **CDN load balancing (9.9)**: the original trigger updated the same table it was defined on, which MySQL forbids.
  The server is now chosen when the connection is created, and rebalancing is done by a scheduled event.
- **Events 9.15 and 9.16** referenced a misspelled table and a non-existent column; both now run correctly.
- **Top-10 queries** (7.5 and analytic 1) ranked each film in its own partition or applied `LIMIT` without ordering;
  they now return the real ranking.
- **Recommendations (7.8, 9.15)**: a `LEFT JOIN` condition excluded films nobody had watched and could include films
  the user had already seen; they are now based on `NOT EXISTS`.
- **Smaller fixes**: due-invoice date range (7.3), month/year filter (7.1), exact age computation (9.5),
  decimal streaming hours (7.6, 9.10), `IS NOT NULL` check (9.3), release-year trigger on the right table (9.1),
  format availability check (9.6), UTF-8 (`utf8mb4`) encoding, a few inconsistent sample values.
- Duplicated logic (nearest server, favourite genre, quality score) was moved into reusable functions.

## ⚠️ Known limitations

This is an academic project and some choices are deliberately simplified:

- passwords and card data (including CVV) are stored in plain text, which a real system must never do;
- distances between countries use a Euclidean approximation on latitude/longitude;
- IP addresses are encoded as integers (`a·10⁹ + b·10⁶ + c·10³ + d`) and each country has a single prefix;
- all names, emails and card numbers in the sample data are fictional.

## 👥 Authors

- **Dario Falaschi** - [@Dariofala](https://github.com/Dariofala)
- **Leonardo Lentini** - [@LeonardoLentini](https://github.com/LeonardoLentini)

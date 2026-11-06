# discourse-robot-mcp

Dodatak za Discourse koji ugrađenom Discourse MCP serveru dodaje alate za IT tim:
Claude (claude.ai, desktop, Claude Code) piše dokumentaciju o urađenom poslu i objavljuje je u IT-Wiki
pod imenom prijavljenog korisnika, bez lozinki.

## Alati

| Alat | Šta radi |
|---|---|
| `robot_search` | Pretraga IT-Wiki i dozvoljenih IT kategorija |
| `robot_read_topic` | Čitanje teme iz dozvoljenih kategorija |
| `robot_check_secrets` | Provjera nacrta na lozinke, ključeve i tokene |
| `robot_wiki_create_topic` | Nova tema u IT-Wiki (odbija tekst sa tajnama) |
| `robot_wiki_reply` | Dopuna postojeće teme u IT-Wiki (odbija tekst sa tajnama) |
| prompt `robot.dokumentuj` | Obrazac i pravila za dokumentaciju |
| `robot_my_tasks` | Moje otvorene, neriješene dodjele (kao `/latest?assigned=<korisnik>&solved=no&status=open`), zadnje javljane na vrhu |
| `robot_task_context` | Prvi post i zadnji odgovori dodijeljene teme |
| `robot_task_reply` | Odgovor u temu koja je trenutno dodijeljena korisniku (status, urađeno, sljedeći koraci, pitanje) |
| prompt `robot.javi` | Tok i obrazac za „javi ovo na forum“ |
| `robot_task_solve` | Označi post kao rješenje u mojoj temi (samo kad korisnik izričito kaže) |
| `robot_task_close` | Zatvori moju temu, po želji uz napomenu (traži `confirmed=true`) |
| `robot_task_reassign` | Prebaci moju temu kolegi iz IT tima, po želji uz napomenu (traži `confirmed=true`) |
| prompt `robot.ocisti` | Pregled starih obaveza i prijedlog šta riješiti, zatvoriti ili prebaciti |

`robot_my_tasks` za čišćenje prima `sort: "oldest"` i `inactive_days`, a za svaku temu vraća `last_poster`
i `waiting_on_it` (zadnji je pisao neko izvan IT tima). `robot_task_reply` i `robot_task_solve` vraćaju
`erp_time_url`: link na ERP formu za upis utrošenog vremena za taj post (postavka `robot_mcp_erp_task_url`,
ista forma kao dugme ✓ u meniju posta).

Wiki alati pišu samo u kategoriju iz `robot_mcp_wiki_category_id`, a čitaju samo iz nje i iz
`robot_mcp_read_categories` (tačne kategorije, bez potkategorija).

Alati za zadatke ne gledaju kategoriju nego dodjelu (discourse-assign): čitaju i pišu samo u teme koje su
**u tom trenutku** dodijeljene prijavljenom korisniku. Dodjela se provjerava pri svakoj objavi, pa reassign
odmah važi. Za zatvorenu ili riješenu temu traži se dodatna potvrda (`confirm_closed`).
Zatvaranje i prebacivanje se odbijaju bez `confirmed=true`, a prebaciti se može samo članu grupa iz
`robot_mcp_allowed_groups`. Prava foruma i dalje važe (guardian): ko ne može zatvoriti temu na forumu,
ne može ni kroz Claude.

Alate mogu koristiti samo članovi grupa iz `robot_mcp_allowed_groups`.

## Postavljanje

1. Instaliraj plugin (u `app.yml`: `git clone https://github.com/adopilot/discourse-robot-mcp.git`).
2. Uključi `mcp_server_enabled` i `robot_mcp_enabled`, podesi kategorije i grupe.
3. U Admin → MCP uključi `robot_*` alate i promptove (nakon nadogradnje i nove: `robot_task_solve`,
   `robot_task_close`, `robot_task_reassign`, `robot.ocisti`), a grupi IT tima daj dozvole `mcp:content:read` i `mcp:content:write`.
4. U Claudeu dodaj konektor `https://<forum>/mcp`. Svaki korisnik se jednom prijavi svojim forumskim nalogom.

# nuclear_status

Ett Bash-skript som hämtar aktuell information om svensk kärnkraftsproduktion från Nord Pool UMM (Unavailability Management Market) och visar status för Sveriges sex reaktorer:

- Forsmark 1, 2 och 3
- Oskarshamn 3
- Ringhals 3 och 4

För varje reaktor visar skriptet om den är i drift, har reducerad effekt eller är offline. Vid en aktiv störning visas bland annat tillgänglig effekt i MW och procent, störningstyp och orsak samt den rapporterade sluttiden. Avslutningsvis visas en sammanfattning av antal reaktorer i varje status och tillgänglig total effekt.

## Förutsättningar

- Bash
- `curl`
- `jq`
- GNU `date` (används för att tolka datum och visa tider i svensk lokal tid)
- Nätverksåtkomst till Nord Pools UMM API

## Användning

Gör skriptet körbart och starta det från terminalen:

```bash
chmod +x nuclear_status.sh
./nuclear_status.sh
```

Det går också att köra utan att ändra filens behörighet:

```bash
bash nuclear_status.sh
```

Skriptet tar inga kommandoradsargument. Det hämtar data från `https://ummapi.nordpoolgroup.com/messages?limit=500`. Om API-anropet misslyckas försöker det igen upp till tre gånger, med fem sekunders väntan mellan försöken. Vid ett felaktigt API-anrop avslutas skriptet med statuskod `2`.

### Anpassa API-adressen

En annan API-adress kan anges med miljövariabeln `UMM_API`:

```bash
UMM_API="https://ummapi.nordpoolgroup.com/messages?limit=500" ./nuclear_status.sh
```

### Färger

Färger används när utdata går till en terminal. Sätt `NO_COLOR` för att stänga av dem:

```bash
NO_COLOR=1 ./nuclear_status.sh
```

Färger stängs också av automatiskt när utdata inte skrivs direkt till en terminal, till exempel vid omdirigering till en fil.

# Lokale security-tests voor Generative Square

Het rapport staat in [`audits/generative-square-mainnet-security-2026-11-12.md`](../audits/generative-square-mainnet-security-2026-11-12.md).

Deze map test het Generative Square-contract (`GenerativeGrid`) lokaal. Er wordt niets gedeployed en er gaat geen transactie naar LUKSO Mainnet of Testnet.

De productiebron `contracts/contracts/GenerativeGrid.sol` blijft onaangeroerd. `src/GenerativeGrid.sol` is een lokale reconstructie van het gedrag dat op mainnet staat (metadata-JSON zoals die functie on-chain antwoordt). De runtime-bytecode komt dichtbij de mainnet-bytecode, maar is geen exacte match. Dat legt `test_localRuntimeIsNotAnExactMainnetMatch` vast.

## Draaien

Vanuit deze map, met Foundry (hier getest met Foundry 1.9 en solc 0.8.28):

```bash
forge test
```

Een enkel geval:

```bash
forge test --match-test test_overpayRevertsAndRestoresTheSender -vv
```

De compiler-instellingen staan in `foundry.toml`: optimizer aan, 500 runs, Cancun, viaIR uit. Dat is de reconstructie die het dichtst bij de mainnet-bytecode kwam, niet een claim dat de bytes identiek zijn.

De Solidity-afhankelijkheden staan in `lib/` en zijn vastgezet in `lib/VERSIONS.txt`:

- `@lukso/lsp-smart-contracts` 0.14.0
- `@erc725/smart-contracts` 5.2.0
- `@openzeppelin/contracts` 4.9.6
- `forge-std` 1.9.5

ERC725 5.2.0 hoort niet bij de gepubliceerde dependency van LSP 0.14 (die vraagt `^7`). De require-strings van 5.2.0 staan wel in de mainnet-bytecode, en de custom errors van ERC725 6+ niet. De tests gebruiken daarom deze combinatie. Er is geen npm-install nodig.

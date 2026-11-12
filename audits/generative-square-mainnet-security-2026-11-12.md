# Security audit Generative Square (LUKSO Mainnet)

Datum: 12 november 2026 (Europe/Amsterdam).
Contract: `0x33Dd4D3da812e2cc1B3692456470DFDD99659e62` op LUKSO Mainnet (chain id 42).
Repository: `minimalnl/generative-grid`, commit `3e7430273e5cd53b17a9feb15cf3b86b60b5a87a` op `main`.
Mint-UI, alleen gelezen: `minimalnl/stille-feed` (`grid-ad.js`), live site `https://minimalnl.github.io/stille-feed/`.

Er is geen transactie verstuurd naar LUKSO Mainnet, LUKSO Testnet of een ander publiek netwerk. Er is niets gedeployed. Er is geen private key of seed phrase gebruikt. De productiebron `contracts/contracts/GenerativeGrid.sol` is niet gewijzigd. `0x7070b7Cb8fAe99B6C7DDd0eaBe831DCb6c3047FD` is niet de owner en wordt dat in dit rapport ook nergens als aanbeveling.

De lokale tests staan in `audit/` en draaien met `forge test`. Ze deployen een reconstructie in het Foundry-proces. Ze bevatten geen broadcast-script en geen aanroep naar het live adres.

## Kort oordeel

De mintprijs, de voorraadgrens, `withdraw` en de owner-checks doen wat de bron beschrijft, en dat is lokaal getest. De zeven al geminte stukken hebben seeds die exact uit de formule in de bron volgen. Het contract is geen proxy.

Twee dingen staan daar los van. De GitHub-bron op `main` is niet de bron die gedeployed is: `tokenMetadataJSON` op keten levert een andere JSON dan het bestand in deze commit. En de runtime-bytecode is geen exacte match met de beste lokale reconstructie (15190 bytes op keten, 15158 lokaal). Het gedrag dat we via `eth_call` hebben gelezen, klopt met de reconstructie. De ontbrekende 32 bytes zijn niet verklaard.

De enige door een aanvaller bruikbare bevinding is dat een LSP1-ontvanger de mint kan terugdraaien nadat de seed al vaststaat. Een gewone EOA kan dat niet. Er is geen pad gevonden waarmee een vreemde het saldo of de metadata wegneemt.

## De vier vragen

### 1. Wat is daadwerkelijk veilig getest?

Alleen lokaal, plus read-only reads op mainnet.

- De volledige Foundry-suite: `cd audit && forge test`. Foundry 1.9.0, solc 0.8.28. Resultaat: **37 geslaagd, 0 gefaald, 0 overgeslagen**.
- Elke gevraagde misbruikpoging heeft een test die het echte resultaat vastlegt: te weinig, te veel en geen betaling; prijsgrenzen op 100/101, 200/201 en 900/901; mint voorbij 1000; LSP1-reentrancy en seed-afwijzing; `withdraw` door een vreemde, door `0x7070…` en door een terugkerende ontvanger; owner-rechten op metadata en royalty's; seedformule, inclusief de zeven historische mainnet-seeds.
- Read-only op `https://rpc.mainnet.lukso.network`, laatst herlezen op block **8769224**: `owner`, `minted`, `totalSupply`, `BASE_PRICE`, `currentPrice`, `priceFor` op de grenzen, `MAX_SUPPLY`, `TIER_SIZE`, saldo, `imageBaseURI`, LSP18-bytes, `supportsInterface`, codesize, EIP-1967-slots, en de bytecode van de owner- en vault-proxy.
- De zeven mint-transacties en de ene `withdraw` zijn uit de logs gelezen. De seeds zijn nagerekend uit `mixHash`, parent hash, `msg.sender` en tokennummer. Alle zeven kloppen.
- De mint-UI is statisch gelezen in `grid-ad.js`. De bestaande node-tests van stille-feed zijn in een tijdelijke kloon gedraaid, zonder die repo te wijzigen: **29 geslaagd, 0 gefaald**.

### 2. Wat blijft onzeker?

- De runtime-bytecode matcht niet. Het IPFS-metadatadocument van de deploy (`QmWr3sqY9nQsc1oHjEy63zSD4fJkeZ9p5FoSGGCgtxeQt8`) was niet op te halen. Sourcify ondersteunt chain 42 niet. Blockscout heeft geen geverifieerde bron. Daardoor zijn optimizer-runs, bronpaden en de exacte package-lock van de deploy niet hersteld. Het verschil is 32 bytes code, niet alleen een andere metadata-hash: beide CBOR-suffixen zijn even lang.
- De LSP8-ouder in de tests is `@lukso/lsp-smart-contracts` 0.14.0, gecompileerd tegen `@erc725/smart-contracts` 5.2.0 en OpenZeppelin 4.9.6. Die ERC725-versie is niet de gepubliceerde dependency van LSP 0.14 (`^7`). Ze is gekozen omdat de require-strings van 5.2.0 in de bytecode staan en de custom errors van ERC725 6+ niet. Het blijft een reconstructie.
- We hebben de Universal Profile-implementatie `0x3024d38ea2434ba6635003dc1bdc0dab5882ed4f` niet inhoudelijk geaudit. Wel is gezien dat de zeven mints naar EOA's en UP's zijn gelukt, dus de ontvangers van díe mints hebben de LSP1-callback niet geweigerd.
- Een block proposer kent `prevrandao` op het moment dat hij de transactie opneemt. Hoeveel vrijheid een LUKSO-proposer daar praktisch heeft, is niet uitgevoerd. De formule zelf wel.
- De website is niet in een browser bediend. Dat was bewust: geen browser-sturing. De UI-conclusies komen uit de bron en uit de node-tests.
- Er is geen permit- of handtekening-mint. Dat pad bestaat niet in dit contract en is dus niet getest.
- Modulo-bias van `2^256 % 1_000_000_000` is niet statistisch gemeten. Het restant is verwaarloosbaar tegenover `SEED_RANGE`; dat is een rekenkundige observatie, geen test.
- Een geforceerde LYX-storting na Cancun (de oude `selfdestruct`-weg) is niet gesimuleerd. Een gewone transfer naar het contract keert terug (`test_directEthTransferReverts`).

### 3. Welke problemen kunnen op de bestaande deployment worden opgelost?

Alleen door de huidige owner `0x52224e802F722A3F3f1de8b2157597ae7fEfffD1`, en alleen met functies die het contract al heeft. Niets hiervan is uitgevoerd.

- Nieuwe mints krijgen de berekende metadata (`icon` leeg, plaatjes 2400 én 600) tot de owner per token `setDataForTokenId` schrijft. Tokens 1 tot en met 7 hebben die override al (allebei 2400). Dezelfde knop in de mint-UI doet dat voor latere tokens. Dat is de enige manier om het Universal Everything-beeld te corrigeren. De functie `tokenMetadataJSON` zelf is niet te vervangen.
- `setImageBaseURI` kan de host verplaatsen. Het script en de seeds blijven staan.
- `setData` op `LSP18RoyaltiesRecipients` kan het royalty-record terugzetten als het ooit verandert. Nu staat het op 5% naar `0x5222…`. De constructor weigert meer dan 100%; `setData` daarna niet. Een te hoge waarde is door de owner weer te overschrijven, de ontbrekende check niet.
- `withdraw(address)` kan naar een ander adres dan een weigerende ontvanger. De UI stuurt naar de owner-UP. Dat is op 5 november 2026 al een keer gelukt, voor exact `0.4375` LYX. Niet naar `address(0)` sturen: die call slaagt en verbrandt het saldo. Niet `renounceOwnership` aanroepen: daarna kan niemand meer uitkeren of metadata schrijven, terwijl minten doorgaat.

Niet doen: ownership overdragen aan `0x7070b7Cb8fAe99B6C7DDd0eaBe831DCb6c3047FD`. Dat adres is de kunstenaarskluis, een andere Universal Profile, en heeft geen owner-rechten. `test_vaultAddressIsNotOwnerAndCannotWithdrawOrRewrite` laat zien dat aanroepen vanaf dat adres worden geweigerd. Dit rapport beveelt geen ownership-wijziging aan.

### 4. Welke problemen vereisen eventueel een nieuw contract?

- De seed vóór de LSP1-callback zetten, zodat een ontvanger een ongewenste seed kan afwijzen. De zeven bestaande seeds zijn al opgeslagen en veranderen niet mee.
- Een pauze, of een andere mintprijs, een andere `MAX_SUPPLY`, of een ander script. Geen van die waarden heeft een setter. `pause()`, `setScript` en `setBasePrice` bestaan niet (`test_compromisedOwnerCannotChangeScriptBasePriceOrSeeds`).
- De berekende metadata gelijk trekken met de GitHub-versie (icoon 600, images alleen 2400). Op dit contract blijft de oude functie de fallback voor tokens zonder override.
- Een nul-check in `withdraw`, een bovengrens op latere royalty-`setData`, of het verwijderen van `renounceOwnership`.
- Elk byteverschil dat in de ontbrekende 32 bytes zou zitten. Zolang die bytes niet zijn verklaard, is een nieuw contract de enige manier om een bekende bron byte-identiek te deployen. Dat is geen advies om nu te redeployen. De gelezen economische functies kloppen met de reconstructie.

## Stap 1 — Komt de bron overeen met de keten?

**Nee. Geen exacte match, en ook geen match-op-metadata-na.**

| | Keten | Lokale reconstructie |
| --- | --- | --- |
| Runtime | 15190 bytes | 15158 bytes |
| solc uit CBOR | `0x00081c` = 0.8.28 | 0.8.28 |
| Optimizer | niet hersteld uit metadata | aan, 500 runs, de dichtstbijzijnde stabiele grootte |
| viaIR | onwaarschijnlijk: een viaIR-build werd duidelijk korter dan 15190 | uit |
| EVM | PUSH0 (`0x5f`) en MCOPY (`0x5e`) aanwezig, dus Cancun of nieuwer | Cancun |
| Metadata | IPFS `12207e6588e62b86010475e1087d10d1b57fc4ff300be9dac9fa7ba4e2231ff74f296` | andere code-hash, vastgelegd door de test |

De CBOR-suffix van de runtime eindigt op `a26469706673582212207e6588e6…64736f6c634300081c0033`. Een metadata-only verschil zou dezelfde lengte hebben. Het verschil van 32 bytes zit dus in de code. `test_localRuntimeIsNotAnExactMainnetMatch` leest `audit/fixtures/mainnet-runtime.hex` en eist lengte 15190 tegen 15158 en een andere `keccak256`.

Sourcify `v2` antwoordt `unsupported_chain` voor chain 42. De Blockscout-API van `https://explorer.execution.mainnet.lukso.network` geeft geen geverifieerde bron (`is_verified` false, `proxy_type` null). IPFS-gateways leverden het compiler-JSON niet. Daarom is de optimizer-run niet uit de deploy zelf gelezen, maar gezocht: rond 500 runs blijft de reconstructie op 15158 bytes en springt daarna naar een grotere runtime, nooit naar 15190.

### Geen proxy

EIP-1967 implementation-, admin- en beacon-slot, en het EIP-1822-slot, zijn op block 8769224 alle `0x00`. Codesize 15190. Er is geen implementation en geen admin om apart te auditen. Het contract is het contract.

### Afhankelijkheden die de bytecode wel verraadt

Aanwezig in de runtime: de strings `Ownable: caller is not the owner` en `Ownable: new owner is the zero address`, en de custom error `ERC725Y_MsgValueDisallowed()` (`0xf36ba737`). Afwezig: `OwnableCallerNotTheOwner` (`0xbf1169c5`) en `OwnableCannotSetZeroAddressAsOwner` (`0x1ad8836c`). Die strings horen bij `@erc725/smart-contracts` 4.2 en 5.2. De custom errors beginnen bij ERC725 6. De gepubliceerde `@lukso/lsp8-contracts` 0.15+ en `lsp-smart-contracts` 0.12+ hangen aan ERC725 `^6` of `^7` en zouden die strings niet produceren.

Ook aanwezig: `LSP8TokenIdAlreadyMinted`, `LSP8CannotSendToAddressZero`, `LSP8NotifyTokenReceiverIsEOA`, `LSP8NotifyTokenReceiverContractMissingLSP1Interface`, `NoExtensionFoundForFunctionSelector`. `supportsInterface(0x3a271706)` is true. Dat is de LSP8-interface-id van lsp-smart-contracts 0.14.0, niet de oude id `0x1ae9ba1f` van 0.11. `supportsInterface(0x80ac58cd)` (ERC-721) is false.

De tests gebruiken daarom LSP 0.14.0-bron, ERC725 5.2.0 en OpenZeppelin 4.9.6. Die combinatie compileert. Ze is niet de lockfile die LSP 0.14 publiceert. OpenZeppelin 4.9.0 tot 4.9.5 gaven een nog kortere runtime (15146). 4.9.6 geeft 15158. Geen van die builds haalt 15190.

### Constructor en deploy

Creatie-transactie `0xfd4115600f7014835842c9e9c66707d45a0b2a2870e7270945b409dc6bb4ce20`, status succes, block 8723089, timestamp 2026-11-05T16:47:24Z. Afzender `0x264E639aDb6E5EB3B9324f48ec3c088eC806a947`, codesize 0. Creatiecode zonder argumenten 17201 bytes, argumenten 2208 bytes.

Afgelezen argumenten:

- name `Generative Square`, symbol `SQUARE`
- owner `0x52224e802F722A3F3f1de8b2157597ae7fEfffD1`
- `basePrice` `62500000000000000` wei = 0,0625 LYX
- image base URI `https://minimalnl.github.io/stille-feed/gg/42/`
- royalty-ontvanger dezelfde `0x5222…`, punten `5000`
- script: het on-chain p5-script (`p5.js@1.9.0`, `WERK_MAAT` 2400, drie achtergronden, drie vierkantkleuren)

`contracts/contracts/GenerativeGrid.sol` is in git toegevoegd in commit `3e74302` op 2026-11-05 20:49 +0100, ná de deploy, met de commitboodschap die de metadata-JSON voor Universal Everything aanpast. Die aanpassing staat niet op keten. `tokenMetadataJSON(1)` geeft `icon: []` en images met zowel `1.png` (2400) als `1-600.png` (600). De GitHub-functie zet het 600px-bestand in `icon` en alleen het 2400px-bestand in `images`. `test_githubSourceMetadataDiffersFromTheDeployedShape` deployt beide en laat het verschil zien. `getDataForTokenId` voor tokens 1–7 geeft wél een opgeslagen override: icon én images allebei alleen het 2400px-bestand. Opgeslagen data wint van de berekende JSON. Een nieuw token valt terug op de oude berekende vorm tot de owner opnieuw schrijft.

### On-chain parameters

Gelezen met `eth_call` op `https://rpc.mainnet.lukso.network`, block 8769224. Chain id 42. Een eerdere read van `https://42.rpc.thirdweb.com` gaf dezelfde chain id. Explorer: `https://explorer.execution.mainnet.lukso.network`.

| Parameter | Waarde |
| --- | --- |
| `owner()` | `0x52224e802F722A3F3f1de8b2157597ae7fEfffD1` |
| `0x7070…` owner? | Nee. Zelfde soort proxy, ander adres. |
| `MAX_SUPPLY` | 1000 |
| `TIER_SIZE` | 100 |
| `BASE_PRICE` | 62500000000000000 wei (0,0625 LYX) |
| `currentPrice()` | dezelfde 0,0625 LYX, want `minted` is 7 |
| `priceFor(1)` en `priceFor(100)` | 0,0625 LYX |
| `priceFor(101)` en `priceFor(200)` | 0,125 LYX |
| `priceFor(201)` | 0,25 LYX |
| `priceFor(900)` | 16 LYX |
| `priceFor(901)` en `priceFor(1000)` | 32 LYX |
| `priceFor(0)` en `priceFor(1001)` | 0 |
| `minted()` / `totalSupply()` | 7 / 7 |
| Saldo | 0 |
| `imageBaseURI` | `https://minimalnl.github.io/stille-feed/gg/42/` |
| LSP4 name / symbol | Generative Square / SQUARE |
| LSP8 `0x3a271706` | true |
| ERC-721 `0x80ac58cd` | false |
| LSP18 `getData(0xc0569ca6…)` | `0x001cffffffff52224e802f722a3f3f1de8b2157597ae7fefffd100001388` |
| Royalty | interface `0xffffffff`, ontvanger `0x5222…`, 5000 / 100000 = 5% |
| Pauze | geen functie. `pause()` valt door de LSP17-fallback |

De owner en de kluis zijn allebei EIP-1167-proxies van 45 bytes naar `0x3024d38ea2434ba6635003dc1bdc0dab5882ed4f`:

`0x363d3d373d3d3d363d73` + implementation + `5af43d82803e903d91602b57fd5bf3`.

`owner()` van de NFT is de proxy `0x5222…`, niet de controller erachter en niet `0x7070…`.

Mints, allemaal tegen 0,0625 LYX. De seed gebruikt `msg.sender` van `mint`, dus het UP-adres als een profiel mint, niet de sleutel die de transactie heeft ondertekend.

| Token | Ontvanger (`msg.sender`) | Seed | Block |
| --- | --- | --- | --- |
| 1 | `0x7777c761e451D44F2B7C01D94318996128bc051d` (EOA, ook `tx.from`) | 858479922 | 8723157 |
| 2 | `0x5222…` | 601749066 | 8723338 |
| 3 | `0x5222…` | 839658880 | 8723369 |
| 4 | `0x7070…` | 176084045 | 8723384 |
| 5 | `0x7070…` | 776970099 | 8723385 |
| 6 | `0x7070…` | 356576559 | 8723387 |
| 7 | `0x7070…` | 118881353 | 8723768 |

`withdraw` eenmaal, in `0x8fcd06e0022f182062dd74c8cf4e2bfbb601dd6ebf87d792ae2a1693106b7e8b`, block 8723901, naar `0x5222…`, bedrag `437500000000000000` wei. Dat is 7 × 0,0625 LYX. Het saldo is daarna 0.

## A. Bewezen kwetsbaarheden

Dit zijn gaten die een aanroeper of de owner daadwerkelijk kan raken. Ze zijn geen diefstal van andermans token en geen manier om onder de prijs te minten.

### A1. Middel — een LSP1-ontvanger kan de seed afwijzen

`mint` schrijft `minted` en `seedOf` en roept daarna `_mint(..., force = true)`. Ondersteunt de ontvanger LSP1 (`supportsInterface(0x6bb56a14)`), dan roept LSP8 `universalReceiver` aan met type id `0x0b084a55ebf70fd3c06fd755269dac2212c4d3f0f4d09079780bfa50c1b2984d`. Een revert in die callback draait de hele mint terug, inclusief betaling en seed. Alleen het gas is weg. De aanvaller kan opnieuw proberen met een andere `prevrandao` of een ander adres.

Een contract zonder LSP1 kan gewoon minten: de interface-check is een `staticcall`, een mislukking wordt bij `force = true` overgeslagen. Een gewone EOA heeft dus geen callback. Een eigen contract, of een Universal Profile met een ontvanger die op de seed revert, wel.

Het script kiest de achtergrond met `seed % 3` uit drie kleuren, en de vierkantkleur uit drie waarden via `randomSeed(SEED)`. Die grove eigenschappen zijn goedkoop te malen. De korrel hangt van veel `random()`-trekkingen af en is dat niet.

De zeven bestaande tokens zijn al geaccepteerd. Hun seeds staan vast. Dit is niet te dichten op het live contract.

Bewijs: `test_lsp1ReceiverCanRejectAnEvenSeedAndRollTheMintBack` (even seed revert, saldo en `minted` blijven 0, oneven seed mint wel). Aanvullend: `test_contractWithoutLsp1CanStillMint`, `test_staticcallHookCannotMintASecondToken`.

Impact nu: niemand heeft daarmee andermans stuk of het saldo gepakt. Een latere minter kan wel zijn eigen grove uiterlijk sturen. De UI mint vanaf het verbonden account; een UP die de standaardontvanger houdt, mint door, zoals tokens 2–7.

### A2. Laag — `setData` omzeilt het royalty-plafond

De constructor revert met `RoyaltyTooHigh` boven `100000`. `setData` is `onlyOwner` en schrijft de LSP18-bytes zonder die check. Een owner kan punten boven 100% publiceren. Marketplaces kunnen dat negeren. De transfer zelf betaalt de royalty niet (zie B7). De live waarde is 5% en is door de owner weer te corrigeren. De check zelf komt niet terug zonder nieuw contract.

Bewijs: `test_constructorRejectsRoyaltyAboveTheBasis`, `test_ownerCanChangeImagesRoyaltiesAndPerTokenMetadata`.

### A3. Laag — `withdraw(address(0))` verbrandt het saldo

`withdraw` doet `to.call{value: amount}("")` zonder nul-check. Een call naar `address(0)` slaagt en het LYX zit daarna op het nul-adres. Alleen de owner kan dit. De UI stuurt naar `0x5222…`, en de enige historische withdraw deed dat ook. Een gecompromitteerde owner kan het saldo verbranden in plaats van stelen. Niet te patchen op dit contract.

Bewijs: `test_withdrawToAddressZeroBurnsTheBalance`.

## B. Ontwerpkeuzes, inclusief wat de tests als bescherming tonen

### B1. Informatief — de prijs is exact, te veel wordt niet geaccepteerd

`msg.value` moet gelijk zijn aan `priceFor(minted + 1)`. Te weinig, te veel en nul reverten met `WrongPrice`. Er is geen refund-tak, omdat de hele transactie terugdraait. De verzender houdt zijn LYX, op het gas na.

Bewijs: `test_unpaidMintRevertsAndMovesNoValue`, `test_underpayRevertsAndMovesNoValue`, `test_overpayRevertsAndRestoresTheSender`, `test_exactPriceMintsAndKeepsThePayment`.

De prijs verdubbelt elke 100: `BASE_PRICE << ((number - 1) / 100)`, en 0 buiten 1..1000. Shift 9 voor nummers 901–1000 geeft 0,0625 × 512 = 32 LYX. Geen overflow op `MAX_SUPPLY`. `priceFor` op de keten geeft dezelfde wei-waarden als de test.

Bewijs: `test_priceForMatchesTheDoublingTiersReadOnMainnet`, `test_mintChargesTheNewTierAt100And200And900`.

Een afgekeurde transactie die nog de prijs van het vorige tier meestuurt, nadat de grens al gepasseerd is, revert. Vooruitbetalen van het duurdere tier terwijl het goedkopere nog geldt, revert ook.

Bewijs: `test_staleCheaperTierPriceReverts`, `test_prepayingTheNextTierWhileStillInTheOldOneReverts`.

### B2. Informatief — mint 1001 bestaat niet

Na nummer 1000 revert `mint` met `SoldOut`, ook als er LYX meegaat. `currentPrice` is dan 0, maar de sold-out-check komt eerst.

Bewijs: `test_mintPastMaxSupplyRevertsSoldOut`.

### B3. Informatief — reentrancy mint een tweede stuk alleen tegen betaling

Een tweede `mint` vanuit `universalReceiver` zonder nieuw `msg.value` laat de hele mint falen (`WrongPrice`). Met een tweede betaling komen er twee opeenvolgende tokens, allebei van de aanvaller, allebei betaald. Hetzelfde token id wordt niet twee keer uitgegeven: `minted` is al verhoogd. De `supportsInterface`-check is een `staticcall` en kan geen tweede mint laten landen.

Bewijs: `test_reentrantMintWithoutASecondPaymentRevertsTheWholeMint`, `test_reentrantMintPaysForASecondTokenAndCannotDuplicateTheId`, `test_staticcallHookCannotMintASecondToken`.

Er is geen publieke `burn`. `totalSupply` en `minted` lopen daardoor niet uit elkaar via een burn-pad. Een onbekende `burn(bytes32,bytes)` revert.

Bewijs: `test_burnSelectorIsNotImplemented`.

### B4. Informatief — `withdraw` is alleen voor de owner, en een boze ontvanger blokkeert het saldo niet blijvend

Een vreemde, inclusief `0x7070…`, krijgt `Ownable: caller is not the owner` op `withdraw`, `setImageBaseURI`, `setData`, `setDataForTokenId`, `transferOwnership` en `renounceOwnership`.

Een ontvanger die in `receive` revert, laat díe `withdraw` falen met `WithdrawFailed`. Het saldo blijft. Een volgende `withdraw` naar een EOA slaagt. Een owner-contract dat tijdens de ontvangst opnieuw `withdraw` aanroept, ziet een leeg saldo en wordt niet dubbel betaald. Het event `Withdrawn` gaat vóór de call de deur uit; bij een revert verdwijnt ook het event.

Bewijs: `test_unauthorizedWithdrawReverts`, `test_vaultAddressIsNotOwnerAndCannotWithdrawOrRewrite`, `test_ownerWithdrawPaysAnEoa`, `test_revertingReceiverDoesNotBrickALaterWithdraw`, `test_reenteringOwnerCannotWithdrawTwice`.

Dit is push-betaling met een vrije `to`. De UI biedt alleen de owner aan. Als die UP ooit zou weigeren, kan de owner nog steeds een ander adres kiezen. Dat is geen permanente blokkade.

### B5. Middel als de owner-sleutel weg is — metadata en royalty's zijn owner-macht, het werk zelf niet

Alleen de owner wijzigt `imageBaseURI`, ERC725Y-data (inclusief LSP18) en per-token metadata. Een opgeslagen `LSP4Metadata` wint van `tokenMetadataJSON`. Een vreemde wordt geweigerd.

De owner kan het script, `BASE_PRICE`, `MAX_SUPPLY`, `SCRIPT_LIBRARY` en een al geschreven seed niet veranderen. Er is geen pauze. Mint blijft publiek.

`transferOwnership` naar het nul-adres revert. `renounceOwnership` zet de owner op nul. Daarna reverten `withdraw` en `setImageBaseURI`, en mint gaat door. Nieuwe opbrengst zou dan vastzitten. Dat is het Ownable-gedrag van ERC725 5.2, geen extern aanvalspad. De owner moet die functie niet aanroepen. Weghalen kan alleen met een nieuw contract.

Bewijs: `test_ownerCanChangeImagesRoyaltiesAndPerTokenMetadata`, `test_compromisedOwnerCannotChangeScriptBasePriceOrSeeds`, `test_renounceOwnershipFreezesWithdrawAndMetadataButNotMint`, `test_transferOwnershipMovesControlAndRejectsZero`.

`imageBaseURI` wordt ongeëscaped in de JSON geplakt. De huidige URI is veilig. Een owner kan de berekende JSON breken. Tokens met een override gebruiken die JSON niet. Bewijs: `test_unescapedImageBaseCanBreakComputedJson`.

### B6. Middel als documentatie, laag voor de zeven bestaande tokens — GitHub wijkt af van de keten

De functie op keten is de oude JSON. De commit op `main` is de nieuwe. Wie deze repository als “het live contract” leest, leest de verkeerde metadata-functie. De zeven tokens tonen door de override al het 2400px-beeld. Een achtste mint toont, tot de owner schrijft, `icon: []` en beide formaten. De UI zegt dat ook (`GGUeFix.LIMITATION` in `grid-ad.js`).

Bewijs: `test_githubSourceMetadataDiffersFromTheDeployedShape`, `test_reconstructionMetadataMatchesTheDeployedJsonShape`, plus de `eth_call`s hierboven.

### B7. Informatief — 5% royalty is een record, geen betaling

De LSP18-bytes kloppen met 5% naar `0x5222…` voor interface `0xffffffff`. `transfer` verplaatst het token en laat het LYX-saldo en het royalty-record met rust. Een marketplace moet het record zelf lezen. Het contract dwingt het niet af bij een LSP8-transfer.

Bewijs: `test_constructorRoyaltyIsFivePercentAndTransferDoesNotPayIt`.

### B8. Informatief — de seed is reproduceerbaar en niet alleen het mintvolgnummer

Formule, dezelfde als in de bron en als in de zeven mainnet-receipts:

```text
uint256(keccak256(abi.encode(block.prevrandao, blockhash(block.number - 1), msg.sender, number))) % 1_000_000_000
```

Op LUKSO levert `cast block` het RANDAO-veld als `mixHash`. `prevRandao` in de JSON is leeg. Met `mixHash` als `prevrandao` kloppen alle zeven seeds. `test_mainnetSeedsMatchPrevrandaoParentHashSenderAndNumber` legt die inputs vast.

`seedOf` blijft staan na de mint. Twee verzenders in hetzelfde blok krijgen verschillende seeds, ook als je voor beiden nummer 1 voorspelt. Hetzelfde adres en twee nummers in hetzelfde blok krijgen verschillende seeds. Een andere `prevrandao` verandert de seed voor hetzelfde adres en nummer. Het volgnummer kiest het token id en is één van vier inputs. Het bepaalt het beeld niet alleen.

Bewijs: `test_mainnetSeedsMatchPrevrandaoParentHashSenderAndNumber`, `test_twoMintersSameBlockGetSequentialIdsAndDifferentSeeds`, `test_sameSenderSameBlockDifferentNumbersGetDifferentSeeds`, `test_prevrandaoChangesTheSeedForTheSameSenderAndNumber`, `test_exactPriceMintsAndKeepsThePayment`.

Een frontrunner koopt het volgende nummer, met zijn eigen `msg.sender` in de seed. Hij krijgt niet het beeld dat het slachtoffer zou hebben gekregen. Op een prijsgrens betaalt hij de nieuwe prijs of zijn transactie revert (B1).

### B9. Informatief — gewone LYX-transfers komen niet binnen

Een call met waarde en lege calldata revert. Het mintpad is de manier om het saldo te vullen, plus de owner die dat saldo opneemt. Bewijs: `test_directEthTransferReverts`.

## C. Hypothetische risico's

Niet uitgevoerd als aanval, wel benoemd zodat ze niet met A worden verward.

- **Gecompromitteerde owner-UP.** De aanvaller kan het saldo opnemen, beelden en royalty's herschrijven, ownership doorgeven of afstand doen. Hij kan het script, de seeds, de prijs en de voorraad niet wijzigen en de mint niet stoppen. Bestaande seeds blijven de bron van het beeld. Dit is het vertrouwensmodel van een owner, geen bug in de checks. `test_compromisedOwnerCannotChangeScriptBasePriceOrSeeds` dekt de grens. De UP-sleutels zelf zijn niet onderzocht.
- **Proposer.** `prevrandao` is bekend voor wie het blok bouwt. Opnemen of weglaten van een mint-transactie verschuift welk blok, en dus welke seed, een minter krijgt. De proposer zet `prevrandao` niet vrij. Niet gesimuleerd voorbij de formule.
- **De 32 onverklaarde bytes.** Alles wat we hebben áángeroepen klopt. Een verschil in een pad dat we niet hebben aangeroepen is niet uit te sluiten. Daarom staat de mismatch in de test, in plaats van een groene “bytecode gelijk”-claim.
- **UI-venster.** De saldocheck in `mint()` is de som van de quotes vóór de lus, zonder gas, en wordt in de lus niet herhaald. `eth_call` dwingt het saldo van `from` niet af op elke client. Een tweede mint in een reeks van vijf kan bij de wallet alsnog op saldo stuklopen. De UI stopt dan en de eerdere geslaagde mints blijven. Geen contractbug.
- **`?ggnet=testnet`.** De query zet de UI op chain 4201 en een ander contract. Het symbool wordt LYXt. Een gedeelde link kan dus naar testnet wijzen. De default is mainnet, chain 42, het live adres.
- **keccak vanaf esm.sh.** De owner-tool laadt `@noble/hashes@1.3.3` van `https://esm.sh` zonder SRI (`grid-ad.js` rond regel 466). De publieke mint gebruikt die import niet. De collection-header gebruikt een vooraf berekende calldata. p5.js 1.9.0 op de site heeft wel SRI. Dit raakt de owner-knop, niet de mintprijs.
- **README van stille-feed.** De README spreekt nog over testnet als huidige stand. `grid-ad.js` regel 12 zegt dat mainnet de default is. De code is leidend.

## Mint-website (stille-feed), alleen gelezen

Bestand: `grid-ad.js` in `minimalnl/stille-feed`. Niet gewijzigd. De node-tests zijn gedraaid in `/tmp/stille-feed`.

| Onderwerp | Wat de code doet | Test |
| --- | --- | --- |
| Netwerk | Default chain 42 en het mainnet-adres. In de Grid weigert `ensureChain` een andere chain. Daarbuiten `wallet_switchEthereumChain` en zo nodig `wallet_addEthereumChain`. | bron regels 12–20 en 736–755. Connect-tests dekken het account, niet de wallet-RPC. |
| Wallet | EIP-6963. In de Grid dwingt `GGConnect` het ingelogde Grid-account af. `assertConnectMethod` staat bij connect alleen `eth_requestAccounts` en `eth_accounts` toe, niet `eth_sendTransaction` of `personal_sign`. | `scripts/gg-connect.test.mjs`: “connect asks for accounts and refuses to send or sign”. |
| Prijs | Lokale formule moet gelijk zijn aan `currentPrice`, anders per nummer `priceFor`. Vóór elke transactie een `eth_call` van `priceFor(n)` en exact dat bedrag als `value`. Hoger dan de knop: stoppen. Lager: wel betalen. | bron 621–628 en 693–708. De contractkant is de Foundry-prijstest. |
| Dubbelklik | `mint` en `connect` zetten `st.busy` vóór het eerste `await` en keren terug als `busy` al waar is. Knoppen gaan uit. | bron 653–658 en 975–980. `claim`, de image-fix en de header hebben eigen busy-vlaggen, dus die delen de mint-lock niet. Ze kunnen elkaar overlappen. Dat mint niet twee keer dezelfde klik. |
| Fouten | `SoldOut` `0x52df9fe5` en `WrongPrice` `0x6871963e` staan in `ERR` en komen overeen met de contract-selectors. Simulatie vóór `eth_sendTransaction`. Receipt-status en het `Minted`-log worden gecontroleerd. Een reeks stopt bij de eerste fout. Gebruiker 4001 wordt “Cancelled.” Onvoldoende saldo wordt herkend. De rest is “Mint failed.” | bron 484 en 642–717. |
| Owner-knoppen | Claim, image-fix en collection header eisen het verbonden account `0x5222…` en weigeren `0x7070…`. Claim roept `withdraw` aan met value 0 en het owner-adres als argument. | `gg-connect.test.mjs` “owner controls still accept only 0x5222 and refuse 0x7070”, en `gg-ue-fix.test.mjs` “owner guard accepts only the contract owner and never 0x7070”. |

De UI-tests zijn geen mainnet-mint. Commando, in de tijdelijke kloon, na een lokale `npm install --no-save` van `ethers@6.13.5`, `@noble/hashes@1.3.3` en `pngjs@7.0.0`:

```bash
node --test scripts/gg-connect.test.mjs scripts/gg-ue-fix.test.mjs \
  scripts/collection-header.test.mjs scripts/collection-header-set.test.mjs
```

Resultaat: 29 geslaagd, 0 gefaald.

De fixture `STORED_OVERRIDE` in `scripts/gg-ue-fix.test.mjs` beschrijft nog een oudere opgeslagen vorm (icoon 600, images 2400). Op de keten, tokens 1–7, zijn icon én images allebei het 2400px-bestand. De fixture is invoer voor “dit moet nog worden bijgewerkt”, niet een verse read. `decideToken` slaat een token over dat al 2400/2400 is. De `COMPUTED`-fixture komt wel overeen met `tokenMetadataJSON` op de keten.

## Testresultaten

```bash
cd audit
forge test
```

Foundry 1.9.0, solc 0.8.28, optimizer 500, Cancun, viaIR uit. Afhankelijkheden staan vendored in `audit/lib/` (`audit/lib/VERSIONS.txt`). Geen npm-install en geen RPC in `foundry.toml`.

```text
Ran 37 tests for test/GenerativeGridSecurity.t.sol:GenerativeGridSecurityTest
Suite result: ok. 37 passed; 0 failed; 0 skipped
```

| Test | Wat hij laat zien |
| --- | --- |
| `test_unpaidMintRevertsAndMovesNoValue` | 0 wei revert `WrongPrice`, niets verplaatst |
| `test_underpayRevertsAndMovesNoValue` | 1 wei te weinig, hetzelfde |
| `test_overpayRevertsAndRestoresTheSender` | 1 wei te veel revert, geen gedeeltelijke mint |
| `test_exactPriceMintsAndKeepsThePayment` | exact 0,0625 LYX mint, saldo blijft op het contract |
| `test_priceForMatchesTheDoublingTiersReadOnMainnet` | 0, 1, 100, 101, 200, 201, 900, 901, 1000, 1001 |
| `test_mintChargesTheNewTierAt100And200And900` | echte mint over die drie grenzen |
| `test_staleCheaperTierPriceReverts` | oude prijs na de grens revert |
| `test_prepayingTheNextTierWhileStillInTheOldOneReverts` | duurdere prijs vóór de grens revert |
| `test_mintPastMaxSupplyRevertsSoldOut` | 1000 lukt, 1001 revert `SoldOut` |
| `test_lsp1ReceiverCanRejectAnEvenSeedAndRollTheMintBack` | A1 |
| `test_reentrantMintWithoutASecondPaymentRevertsTheWholeMint` | tweede mint zonder betaling faalt alles |
| `test_reentrantMintPaysForASecondTokenAndCannotDuplicateTheId` | twee tokens, twee betalingen, geen dubbel id |
| `test_staticcallHookCannotMintASecondToken` | interface-hook mint niet |
| `test_contractWithoutLsp1CanStillMint` | `force = true` levert aan een kaal contract |
| `test_twoMintersSameBlockGetSequentialIdsAndDifferentSeeds` | volgorde is niet het hele beeld |
| `test_sameSenderSameBlockDifferentNumbersGetDifferentSeeds` | nummer verandert de seed |
| `test_prevrandaoChangesTheSeedForTheSameSenderAndNumber` | proposer-veld zit in de seed |
| `test_mainnetSeedsMatchPrevrandaoParentHashSenderAndNumber` | zeven historische seeds |
| `test_vaultAddressIsNotOwnerAndCannotWithdrawOrRewrite` | `0x7070…` is geen owner |
| `test_unauthorizedWithdrawReverts` | vreemde kan niet uitkeren |
| `test_ownerWithdrawPaysAnEoa` | owner kan naar een EOA |
| `test_revertingReceiverDoesNotBrickALaterWithdraw` | één mislukte payout blokkeert niet |
| `test_reenteringOwnerCannotWithdrawTwice` | geen dubbele opname |
| `test_withdrawToAddressZeroBurnsTheBalance` | A3 |
| `test_ownerCanChangeImagesRoyaltiesAndPerTokenMetadata` | owner-macht, inclusief royalty boven 100% |
| `test_constructorRoyaltyIsFivePercentAndTransferDoesNotPayIt` | 5%, transfer betaalt niet |
| `test_constructorRejectsRoyaltyAboveTheBasis` | plafond alleen in de constructor |
| `test_compromisedOwnerCannotChangeScriptBasePriceOrSeeds` | geen pauze, geen script- of prijswijziging |
| `test_renounceOwnershipFreezesWithdrawAndMetadataButNotMint` | afstand bevriest beheer, niet de mint |
| `test_transferOwnershipMovesControlAndRejectsZero` | nul-adres als owner wordt geweigerd |
| `test_directEthTransferReverts` | geen kale LYX-transfer |
| `test_burnSelectorIsNotImplemented` | geen publieke burn |
| `test_unescapedImageBaseCanBreakComputedJson` | owner kan de berekende JSON breken |
| `test_reconstructionMetadataMatchesTheDeployedJsonShape` | `icon: []` en beide formaten |
| `test_githubSourceMetadataDiffersFromTheDeployedShape` | GitHub-JSON is de andere vorm |
| `test_localRuntimeIsNotAnExactMainnetMatch` | 15158 tegen 15190 |
| `test_mintedLivesInSlot7` | de sprong in `minted` voor de grens-tests gebruikt slot 7 |

Wat niet volledig is nagebouwd: de byte-identieke compiler-run, de UP-implementatie, en een browser-sessie op de live site. Dat staat bij vraag 2.

## Buiten scope

De Next.js-app in deze repository is niet de mint-UI en is niet gewijzigd. De Universal Profile-implementatie is alleen herkend als gedeelde proxy van owner en kluis. Marketplace-afhandeling van LSP18, de visuele correctheid van het p5-beeld voorbij de seed, en het testnet-contract `0xF4947C5F85115D9FA6c039Ac459C630370F8F239` zijn niet geaudit.

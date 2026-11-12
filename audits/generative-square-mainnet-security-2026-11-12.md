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

De follow-up onderaan dit rapport (zelfde datum, tweede ronde) verklaart dat lengtegat deels. De 15158-byte build is LSP 0.14.0. De keten gebruikt een latere LSP8, met `minted` in slot 6. Een byte-identieke reconstructie is ook met die bron niet gevonden.

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

## Follow-up 12 november 2026

Tweede ronde op dezelfde branch en dezelfde pull request. Geen mainnet-transactie, geen broadcast, geen wijziging aan `contracts/contracts/GenerativeGrid.sol` of de live site. `0x7070b7Cb8fAe99B6C7DDd0eaBe831DCb6c3047FD` is nergens als owner gezet en wordt hier niet als owner aanbevolen.

De cijfers uit de eerste ronde zijn opnieuw gemeten. Waar ze kloppen, blijft dat zo. Waar ze de keten niet dekten, staat dat hier.

### Wat nu is opgelost

- De 32-byte kloof van de eerste reconstructie is een bronverschil, niet een metadata-hash. LSP 0.14.0 declareert `mapping(address => EnumerableSet.Bytes32Set) _tokenIdsForOperator` en leest of schrijft die mapping nergens. Daardoor staat `minted` in die build in slot 7. Op de keten staat `minted` in slot 6: `eth_getStorageAt` slot 6 is `7` zolang er zeven stukken gemint zijn, slot 8 is de script-string (1684 bytes) en slot 9 is `imageBaseURI` (46 bytes). De lokale suite laat die ongebruikte mapping weg, en `test_mintedLivesInSlot6` eist slot 6. De lengte van die suite-build blijft 15158 bytes: een PUSH1-immediate verandert de lengte niet.
- De 4-byte waarden in de 0.14-runtime en in de mainnet-runtime verschillen op drie errors. Alleen lokaal: `LSP8CannotSendToSelf()` (`0x5d67d6c1`). Alleen op de keten: `LSP8RevokeOperatorNotAuthorized(address,address,bytes32)` (`0x760b5acd`) en `LSP8TokenOwnerChanged(bytes32,address,address)` (`0x5a9c31d3`). Die twee errors, en de layout zonder de ongebruikte mapping, staan in `lukso-network/lsp-smart-contracts` commit `f77b5582a7d190f1f83e349b9ad406f7beb60bb5` (2024-03-04, monorepo op develop). Dezelfde errors staan in `@lukso/lsp8-contracts` vanaf 0.15. Die pakketten hangen aan ERC725 7 of 8.
- De mainnet-runtime bevat de string `Ownable: caller is not the owner` en bevat `OwnableCallerNotTheOwner` (`0xbf1169c5`) niet. ERC725 6.0.0, 7.0.0 en 8.0.0 gebruiken die custom error. De deploy is dus nieuwere LSP8-bron tegen ERC725 5.x gecompileerd. ERC725 5.2.0 compileert die commit, en elke PUSH4 in die build komt ook in de mainnet-runtime voor. Geen selector zit nog maar aan één kant.
- Een contract zonder LSP1 kan de seed lezen nadat `mint` terugkeert en de hele transactie daarna terugdraaien. `test_nonLsp1CallerCanReadTheSeedAndRevertTheMint` doet dat lokaal. De medium-bevinding uit de eerste ronde is daarmee breder dan alleen een LSP1-ontvanger: elke tussenschakel met eigen code kan een seed bekijken en verwerpen. Een EOA kan dat nog steeds niet, want na de mint keert de controle niet naar eigen code terug.
- De owner-UP is gelezen, niet aangepast. Zie hieronder. `0x7070…` heeft op die UP geen permissie-entry.

### Wat open blijft

Een byte-identieke reconstructie is niet bereikt. De dichtstbijzijnde build is 15191 bytes, één byte langer dan de keten, en de opcodes zijn niet dezelfde reeks met één extra byte.

Geprobeerd, telkens met solc 0.8.28, Cancun, viaIR uit, `bytecode_hash = ipfs`, en de immutable `BASE_PRICE` (`62500000000000000`) in de twee PUSH32-plaatsen geplakt voordat er vergeleken werd:

| Bron | OpenZeppelin | optimizer runs | runtime | tegen 15190 |
| --- | --- | --- | --- | --- |
| LSP 0.14.0, slot nog gereserveerd, ERC725 5.2.0 | 4.9.6 | 500 | 15158 | 32 korter |
| dezelfde bron, ongebruikte mapping weg | 4.9.6 | 500 | 15158 | 32 korter |
| commit `f77b5582a7d190f1f83e349b9ad406f7beb60bb5`, ERC725 5.2.0 | 4.9.6 | 220–240 | 15173 | 17 korter |
| dezelfde commit | 4.9.6 | 250 | 15203 | 13 langer |
| dezelfde commit | 4.9.3, 4.9.4 of 4.9.5 | 241–249 | 15161 | 29 korter |
| dezelfde commit | 4.9.3, 4.9.4 of 4.9.5 | 250 en 251 | 15191 | 1 langer |

Een sweep van 1 tot 50000 runs op de 0.14-combinatie en op de maart-2024-bron landde nooit op 15190. OpenZeppelin 4.9.0–4.9.5 waren in de eerste ronde 12 bytes korter dan 4.9.6; dat verschil staat er bij de maart-2024-bron ook. ERC725 6, 7 en 8 vallen af door de Ownable-string. LSP 0.12 en 0.13 hebben een ander LSP8-interface-id dan `0x3a271706`, en de keten antwoordt `true` op dat id.

De 15191-byte build heeft dezelfde PUSH4-set als de keten. De bytes zijn het niet. `SequenceMatcher` op de opcodes zonder immediate geeft ratio 0.9577 (10025 opcodes lokaal, 10080 op de keten, 147 afwijkende stukken). Het eerste rauwe verschil zit op offset 60, in de dispatcher: de sprong is lokaal `0x0743` en op de keten `0x0745`. Vanaf offset 668 wijkt de stack-volgorde af (`PUSH1 4` tegen `DUP3`). De CBOR-suffix is aan beide kanten 53 bytes, vorm `a2646970667358221220…64736f6c634300081c0033` (solc 0.8.28, ipfs). De hash erin verschilt, zoals het hoort wanneer de code verschilt. De twee immutable woorden verklaren de lengte niet: ze zijn 32 bytes aan beide kanten.

Niet stuk voor stuk opnieuw gecompileerd: de LSP8-commits ná `f77b5582` tot de refactor van 26 januari 2026 die LSP8-`require`s door andere custom errors vervangt. Die refactor zou de PUSH4-set veranderen, en de keten matcht de set van `f77b5582`. Een latere commit kan de codegen nog wel veranderen zonder de selectors te veranderen. Dat is precies de resterende byte.

De praktische volgende stap is het standard-json van de oorspronkelijke deploy (solc-input, optimizer-details, en de exacte dependency-commits). Een byte-diff tegen dat artefact sluit het gat. De 15191-byte build is geen match. Instellingen en hashes staan in `audit/reconstruction/SETTINGS.txt`.

### Fork van de live bytecode

`https://rpc.mainnet.lukso.network` dient block 8769224 niet. Zowel die RPC als `https://42.rpc.thirdweb.com` antwoordt:

```text
error code -32000: historical state 725af0942a60cde96376c10233ec9774f17d857154aa945e19a8f82e0278a18f is not available
```

De publieke node bewaart een kort venster. Tijdens het zoeken (laatste block toen 8769549) was 8769421 het oudste block waarvan slot 6 nog leesbaar was, ongeveer 128 blocks. Thirdweb gaf op een tweede lezing HTTP 429.

De fork-tests pinnen daarom block **8769566**, hash `0x796cf66245d1238953eec6b7174cc348aee99c421472d62edae58d4797f9ed22`, timestamp 1794502068 (2026-11-12 16:47:48 UTC). Op dat block is de staat dezelfde als bij 8769224 voor de dingen die we toen lazen: `minted` 7, saldo 0, owner `0x5222…`, codesize 15190, en `keccak256` van de runtime gelijk aan `audit/fixtures/mainnet-runtime.hex`. Het contract is geen proxy, dus dit is dezelfde bytecode als op 8769224.

`forge test` op deze boom: 43 tests, 0 gefaald, 0 overgeslagen. Daarvan 5 in `audit/test/GenerativeGridMainnetFork.t.sol`, allemaal tegen die pin:

| Test | Wat de live bytecode deed |
| --- | --- |
| `test_forkPinsTheBlockAndTheLiveRuntime` | blocknummer 8769566, runtime gelijk aan de fixture |
| `test_forkSupplyPriceAndOwnerMatchTheDeployedState` | owner `0x5222…`, niet de vault, `minted` 7 in slot 6, prijs 0,0625 LYX |
| `test_forkUnpaidUnderExactAndOverpay` | 0, te weinig en te veel reven `WrongPrice`; exacte betaling mint token 8 en laat de codehash staan |
| `test_forkSoldOutUsesTheLiveMintedSlot` | slot 6 op 1000 geeft `SoldOut`; vanaf 999 lukt nummer 1000 voor `priceFor(1000)` = 32 LYX |
| `test_forkVaultCannotWithdrawOrWriteAndOwnerCan` | `0x7070…` faalt op `withdraw`, `setImageBaseURI` en `transferOwnership`; de owner kan uitkeren en de URI schrijven |

Elke call blijft in het Foundry-proces (`vm.createSelectFork`, `vm.prank`, `vm.deal`, `vm.store`). Er is geen broadcast-profiel. `transferOwnership` in de laatste test gaat op de fork naar `0xB0B`, niet naar de vault.

Is 8769566 van de node verdwenen, dan vangt `setUp` de RPC-fout en slaat de vijf tests over. Een nieuwe run zet `FORK_BLOCK` op een block dat de RPC nog dient en controleert dat `minted` en de codehash nog kloppen. Een overgeslagen run is geen geslaagde fork.

### Seed zonder LSP1

`SeedPeekingMinter` heeft geen `supportsInterface` en geen `universalReceiver`. Hij roept `mint` aan, leest `seedOf(minted())`, en revert met `SawSeed(seed)`. De test verwacht die error met de seed uit de formule, en daarna `minted == 0`, saldo 0, en de betaling terug bij de aanroeper. Dat is hetzelfde economische effect als de LSP1-test: de seed is zichtbaar voordat de transactie vastligt, en een contract kan blijven proberen tot de seed bevalt. De eerste ronde koppelde dat aan de LSP1-callback omdat `force = true` die callback aanroept. Deze test laat zien dat de callback niet nodig is zodra de aanroeper zelf een contract is.

### Owner-UP `0x5222…`, alleen gelezen

`0x52224e802F722A3F3f1de8b2157597ae7fEfffD1` is een EIP-1167-proxy naar `0x3024d38ea2434ba6635003dc1bdc0dab5882ed4f`. `owner()` op die proxy is `0x538f51ae89406B7555FA19F2Dd27021D06C5addE`, zelf een EIP-1167-proxy naar `LSP6KeyManagerInit` op `0x2fe3aed98684e7351ad2d408a43ce09a738bf8a4`. `target()` van de key manager wijst terug naar de UP. De vault `0x7070…` is een aparte UP naar dezelfde implementatie `0x3024…` en is geen controller van `0x5222…`.

`AddressPermissions[]` op de UP heeft lengte 3. Sleutels volgens LSP2: `bytes10`-prefix, dan `0x0000`, dan het adres. Permissiebits uit de geverifieerde `LSP6Constants` van de key-manager-implementatie (solc 0.8.17 op de explorer).

| Controller | Wat het is | `permissions` | Gevolg voor dit NFT-contract |
| --- | --- | --- | --- |
| `0x7870c5b8bc9572a8001c3f96f7ff59961b23500d` | geverifieerd `LSP1UniversalReceiverDelegateUP` | `0x60080` = `REENTRANCY`, `SUPER_SETDATA`, `SETDATA` | Geen `CALL`. Kan het NFT-contract niet aanroepen. `SUPER_SETDATA` slaat alleen de controle over voor gewone ERC725Y-sleutels. Permissie-sleutels eisen `ADDCONTROLLER` of `EDITPERMISSIONS`, en die bits heeft deze delegate niet. |
| `0x7fb53f018c1f8b4d2ee4579dac0eec323eea06a6` | EOA, codesize 0 | `0x7f3f06` | Wel `SUPER_CALL`, `CALL`, `SUPER_TRANSFERVALUE`, `TRANSFERVALUE`, `SUPER_SETDATA`, `SETDATA`, `EDITPERMISSIONS`, `ADDCONTROLLER`, `DEPLOY`, `SIGN`, `ENCRYPT`, `DECRYPT`, `EXECUTE_RELAY_CALL` en de static-call-bits. `AllowedCalls` is leeg. `SUPER_CALL` slaat die lijst over, dus deze EOA kan de UP `withdraw`, `setData`, `setDataForTokenId`, `setImageBaseURI`, `transferOwnership` en `renounceOwnership` op het NFT laten aanroepen. `CHANGEOWNER`, de extension-bits, de universal-receiver-delegate-bits, `REENTRANCY` en beide delegatecall-bits ontbreken. |
| `0xeb7a7b91b5b7188c098cb64dd01f59c9d876566d` | EIP-1167 naar `UniversalProfileInit` `0x52c90985AF970D4E0DC26Cb5D052505278aF32A9` | `0x2` = alleen `ADDCONTROLLER` | Kan het NFT nu niet aanroepen. De geverifieerde key manager eist `ADDCONTROLLER` om een nog lege permissie-sleutel te schrijven, en de bron heeft geen check die het toegekende bitveld tot de eigen bits beperkt. Deze UP kan dus een nieuwe controller aanstellen. |

Geen van de drie heeft `CHANGEOWNER` of `DELEGATECALL`. De key manager zelf vervangen via de LSP6-owner-permissie zit niet in deze set. `transferOwnership` op het NFT is een gewone call, en de EOA met `SUPER_CALL` kan die wel door de UP laten doen. Dat is vastgesteld door de bits en de geverifieerde key-manager-bron te lezen. Er is geen permissie gewijzigd.

`0x7070…` komt in `AddressPermissions[]` niet voor en heeft een lege permissie-sleutel. Die rekening hoort niet de owner van het NFT-contract te worden.

### Tests na deze ronde

`forge test` vanuit `audit/`: 38 tests in `GenerativeGridSecurity.t.sol` en 5 in `GenerativeGridMainnetFork.t.sol`. 43 geslaagd, 0 gefaald, 0 overgeslagen, op de pin hierboven. Nieuw tegenover de 37 van de eerste ronde: de non-LSP1-rollback, `test_mintedLivesInSlot6` in plaats van de slot-7-test, en de vijf fork-tests. De productiebron en de website zijn niet gewijzigd.

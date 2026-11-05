// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {LSP8IdentifiableDigitalAsset} from "@lukso/lsp8-contracts/contracts/LSP8IdentifiableDigitalAsset.sol";
import {_LSP4_TOKEN_TYPE_NFT} from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";
import {_LSP8_TOKENID_FORMAT_NUMBER} from "@lukso/lsp8-contracts/contracts/LSP8Constants.sol";
import {_LSP4_METADATA_KEY} from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title Generative Square
/// @notice 1000 generatieve stukken. Elke mint krijgt een on-chain seed;
///         het p5-script staat onveranderlijk in dit contract, dus elk stuk
///         is altijd opnieuw te tekenen met script() + seedOf(tokenId).
contract GenerativeGrid is LSP8IdentifiableDigitalAsset {
    uint256 public constant MAX_SUPPLY = 1000;
    /// @notice Seeds liggen in [0, SEED_RANGE), net als in de app (p5 randomSeed).
    uint256 public constant SEED_RANGE = 1_000_000_000;

    /// @notice Tokens per price tier; the price doubles every tier.
    uint256 public constant TIER_SIZE = 100;

    /// @notice Price of #1-100 in wei. Mainnet: 0.0625 LYX (-> 0.125, 0.25, 0.5, 1 LYX for #401-500 ...
    ///         32 LYX for #901-1000; all 1000 together: 102,300 x BASE_PRICE = 6,393.75 LYX). Testnet may be lower.
    uint256 public immutable BASE_PRICE;

    /// @notice Aantal gemint (ook = laatst uitgegeven tokenId).
    uint256 public minted;

    /// @notice Seed per tokenId-nummer (1..1000).
    mapping(uint256 => uint256) public seedOf;

    /// @notice De bibliotheek waar het script voor geschreven is.
    string public constant SCRIPT_LIBRARY = "p5.js@1.9.0";

    string private _script;

    /// @notice Where the prerendered PNGs live: image = imageBaseURI + number + ".png"
    ///         (and number + "-600.png" for a small one). Owner can move it; script + seed stay the source of truth.
    string public imageBaseURI;

    /// @dev VerifiableURI header: 0x0000 + keccak256(bytes) method + 32-byte hash length.
    bytes8 private constant _VERIFIABLE_URI_KECCAK = 0x00008019f9b10020;

    /// @notice LSP18 Royalties data key: keccak256("LSP18RoyaltiesRecipients").
    bytes32 public constant LSP18_ROYALTIES_RECIPIENTS = 0xc0569ca6c9180acc2c3590f36330a36ae19015a19f4e85c28a7631e3317e6b9d;
    /// @dev LSP18 points basis: 100_000 = 100%.
    uint32 public constant ROYALTY_BASIS = 100_000;

    event Minted(address indexed to, uint256 indexed number, uint256 seed, uint256 price);
    event Withdrawn(address indexed to, uint256 amount);
    event ImageBaseURIChanged(string uri);

    error SoldOut();
    error WrongPrice(uint256 expected, uint256 sent);
    error WithdrawFailed();
    error UnknownNumber(uint256 number);
    error RoyaltyTooHigh(uint32 points);

    constructor(
        string memory name_,
        string memory symbol_,
        address owner_,
        uint256 basePrice_,
        string memory script_,
        string memory imageBaseURI_,
        address royaltyRecipient_,
        uint32 royaltyPoints_
    )
        LSP8IdentifiableDigitalAsset(
            name_,
            symbol_,
            owner_,
            _LSP4_TOKEN_TYPE_NFT,
            _LSP8_TOKENID_FORMAT_NUMBER
        )
    {
        BASE_PRICE = basePrice_;
        _script = script_;
        imageBaseURI = imageBaseURI_;
        emit ImageBaseURIChanged(imageBaseURI_);
        if (royaltyPoints_ > ROYALTY_BASIS) revert RoyaltyTooHigh(royaltyPoints_);
        // LSP18: (bytes4 interfaceId, address recipient, uint32 points)[CompactBytesArray].
        // interfaceId 0xffffffff = "unknown / plain transfer". Owner can change it later via setData.
        if (royaltyRecipient_ != address(0)) {
            _setData(
                LSP18_ROYALTIES_RECIPIENTS,
                abi.encodePacked(uint16(28), bytes4(0xffffffff), royaltyRecipient_, royaltyPoints_)
            );
        }
    }

    /// @notice Owner can move the image host (e.g. to IPFS later). Existing tokens follow automatically.
    function setImageBaseURI(string calldata uri) external onlyOwner {
        imageBaseURI = uri;
        emit ImageBaseURIChanged(uri);
    }

    /// @notice LSP4Metadata JSON for minted token `number` (built on-chain, never stale).
    function tokenMetadataJSON(uint256 number) public view returns (string memory) {
        if (number == 0 || number > minted) revert UnknownNumber(number);
        string memory n = Strings.toString(number);
        string memory base = imageBaseURI;
        string memory icon = bytes(base).length == 0 ? "[]" : string.concat(
            '[{"width":600,"height":600,"url":"', base, n, '-600.png"}]'
        );
        string memory images = bytes(base).length == 0 ? "[]" : string.concat(
            '[[{"width":2400,"height":2400,"url":"', base, n, '.png"}]]'
        );
        return string.concat(
            '{"LSP4Metadata":{"name":"Generative Square #', n,
            '","description":"One square, its own seed. Script and seed live on-chain.","links":[],"icon":',
            icon, ',"images":',
            images,
            ',"assets":[],"attributes":[{"key":"Seed","value":', Strings.toString(seedOf[number]),
            ',"type":"number"}]}}'
        );
    }

    /// @dev VerifiableURI (keccak256(bytes)) pointing to the JSON as a base64 data: URI.
    function _tokenMetadataValue(uint256 number) internal view returns (bytes memory) {
        bytes memory json = bytes(tokenMetadataJSON(number));
        return abi.encodePacked(_VERIFIABLE_URI_KECCAK, keccak256(json), "data:application/json;base64,", Base64.encode(json));
    }

    /// @dev getDataForTokenId(id, LSP4Metadata) is computed for every minted token, unless the owner
    ///      explicitly stored a value with setDataForTokenId (stored value wins).
    function _getDataForTokenId(bytes32 tokenId, bytes32 dataKey) internal view override returns (bytes memory value) {
        value = super._getDataForTokenId(tokenId, dataKey);
        if (value.length == 0 && dataKey == _LSP4_METADATA_KEY) {
            uint256 number = uint256(tokenId);
            if (number != 0 && number <= minted) value = _tokenMetadataValue(number);
        }
    }

    /// @notice Het p5-script (onveranderlijk, zonder setter).
    function script() external view returns (string memory) {
        return _script;
    }

    /// @notice Price (wei) for mint number `number` (1-based): doubles every 100. 0 if out of range.
    function priceFor(uint256 number) public view returns (uint256) {
        if (number == 0 || number > MAX_SUPPLY) return 0;
        return BASE_PRICE << ((number - 1) / TIER_SIZE); // x1, x2, x4 ... x512
    }

    /// @notice Prijs van de volgende mint (0 = uitverkocht).
    function currentPrice() external view returns (uint256) {
        return priceFor(minted + 1);
    }

    /// @notice Mint het volgende stuk naar de aanroeper. Betaal exact currentPrice().
    /// @dev Exacte prijs (geen refund): voorkomt refund-logica; wie precies op een
    ///      prijsgrens zit en te weinig/te veel stuurt, krijgt een revert en verliest niets.
    function mint() external payable returns (bytes32 tokenId) {
        uint256 number = minted + 1;
        if (number > MAX_SUPPLY) revert SoldOut();
        uint256 price = priceFor(number);
        if (msg.value != price) revert WrongPrice(price, msg.value);

        uint256 seed = uint256(
            keccak256(
                abi.encode(block.prevrandao, blockhash(block.number - 1), msg.sender, number)
            )
        ) % SEED_RANGE;

        // Effects vóór interactie (LSP1-notificatie in _mint) -> reentrancy-veilig.
        minted = number;
        seedOf[number] = seed;
        tokenId = bytes32(number);

        emit Minted(msg.sender, number, seed, price);
        _mint(msg.sender, tokenId, true, "");
        // Lets indexers (universal.page etc.) pick up the per-token metadata without storing it.
        emit TokenIdDataChanged(tokenId, _LSP4_METADATA_KEY, _tokenMetadataValue(number));
    }

    /// @notice Owner haalt de opbrengst op naar `to`.
    function withdraw(address payable to) external onlyOwner {
        uint256 amount = address(this).balance;
        emit Withdrawn(to, amount);
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert WithdrawFailed();
    }
}

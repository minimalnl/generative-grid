// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {GenerativeGrid} from "../src/GenerativeGrid.sol";
import {GenerativeGrid as GitHubGrid} from "../src/github/GenerativeGrid.sol";
import {_LSP4_METADATA_KEY} from "@lukso/lsp-smart-contracts/contracts/LSP4DigitalAssetMetadata/LSP4Constants.sol";
import {
    RejectingReceiver,
    ReenteringMinter,
    StaticReenteringMinter,
    PlainContractMinter,
    RevertingSink,
    ReenteringOwner
} from "./helpers/Attackers.sol";

/// @notice Local defensive tests of the deployed Generative Square behaviour.
///         Every transaction stays inside this Foundry process.
contract GenerativeGridSecurityTest is Test {
    uint256 internal constant BASE = 0.0625 ether;
    uint256 internal constant MINTED_SLOT = 7;

    /// @dev The artist vault. Used only as an account that must fail owner calls.
    ///      No test transfers ownership to this address.
    address internal constant VAULT = 0x7070b7Cb8fAe99B6C7DDd0eaBe831DCb6c3047FD;

    GenerativeGrid internal grid;
    RejectingReceiver internal grinder;
    ReenteringMinter internal reenter;
    RevertingSink internal sink;

    function setUp() public {
        grid = _deployReconstruction(address(this), BASE);
        grinder = new RejectingReceiver(grid);
        reenter = new ReenteringMinter(grid);
        sink = new RevertingSink();
        vm.deal(address(this), 1000 ether);
    }

    receive() external payable {}

    function test_mintedLivesInSlot7() public {
        _mintAs(address(this), 1);
        assertEq(uint256(vm.load(address(grid), bytes32(MINTED_SLOT))), 1);
    }

    function test_unpaidMintRevertsAndMovesNoValue() public {
        uint256 before = address(this).balance;
        vm.expectRevert(abi.encodeWithSelector(GenerativeGrid.WrongPrice.selector, BASE, 0));
        grid.mint{value: 0}();
        assertEq(grid.minted(), 0);
        assertEq(address(grid).balance, 0);
        assertEq(address(this).balance, before);
    }

    function test_underpayRevertsAndMovesNoValue() public {
        uint256 before = address(this).balance;
        vm.expectRevert(abi.encodeWithSelector(GenerativeGrid.WrongPrice.selector, BASE, BASE - 1));
        grid.mint{value: BASE - 1}();
        assertEq(grid.minted(), 0);
        assertEq(address(grid).balance, 0);
        assertEq(address(this).balance, before);
    }

    function test_overpayRevertsAndRestoresTheSender() public {
        uint256 before = address(this).balance;
        vm.expectRevert(abi.encodeWithSelector(GenerativeGrid.WrongPrice.selector, BASE, BASE + 1));
        grid.mint{value: BASE + 1}();
        assertEq(grid.minted(), 0);
        assertEq(address(grid).balance, 0);
        assertEq(address(this).balance, before);
    }

    function test_exactPriceMintsAndKeepsThePayment() public {
        uint256 before = address(this).balance;
        bytes32 id = grid.mint{value: BASE}();
        assertEq(id, bytes32(uint256(1)));
        assertEq(grid.minted(), 1);
        assertEq(grid.totalSupply(), 1);
        assertEq(grid.tokenOwnerOf(id), address(this));
        assertEq(address(grid).balance, BASE);
        assertEq(address(this).balance, before - BASE);
        assertEq(grid.seedOf(1), _predict(address(this), 1));
    }

    function test_priceForMatchesTheDoublingTiersReadOnMainnet() public view {
        assertEq(grid.BASE_PRICE(), 62_500_000_000_000_000);
        assertEq(grid.priceFor(0), 0);
        assertEq(grid.priceFor(1), 62_500_000_000_000_000);
        assertEq(grid.priceFor(100), 62_500_000_000_000_000);
        assertEq(grid.priceFor(101), 125_000_000_000_000_000);
        assertEq(grid.priceFor(200), 125_000_000_000_000_000);
        assertEq(grid.priceFor(201), 250_000_000_000_000_000);
        assertEq(grid.priceFor(900), 16 ether);
        assertEq(grid.priceFor(901), 32 ether);
        assertEq(grid.priceFor(1000), 32 ether);
        assertEq(grid.priceFor(1001), 0);
        assertEq(grid.currentPrice(), grid.priceFor(1));
    }

    function test_mintChargesTheNewTierAt100And200And900() public {
        _jumpAndMintAcross(99, 100, 101);
        _jumpAndMintAcross(199, 200, 201);
        _jumpAndMintAcross(899, 900, 901);
        assertEq(grid.minted(), 901);
        assertEq(grid.seedOf(100), _predict(address(this), 100));
        assertEq(grid.seedOf(901), _predict(address(this), 901));
    }

    function test_staleCheaperTierPriceReverts() public {
        vm.store(address(grid), bytes32(MINTED_SLOT), bytes32(uint256(100)));
        uint256 due = grid.priceFor(101);
        uint256 stale = grid.priceFor(100);
        vm.expectRevert(abi.encodeWithSelector(GenerativeGrid.WrongPrice.selector, due, stale));
        grid.mint{value: stale}();
        assertEq(grid.minted(), 100);
        assertEq(address(grid).balance, 0);
    }

    function test_prepayingTheNextTierWhileStillInTheOldOneReverts() public {
        vm.store(address(grid), bytes32(MINTED_SLOT), bytes32(uint256(99)));
        uint256 due = grid.priceFor(100);
        uint256 nextTier = grid.priceFor(101);
        vm.expectRevert(abi.encodeWithSelector(GenerativeGrid.WrongPrice.selector, due, nextTier));
        grid.mint{value: nextTier}();
        assertEq(grid.minted(), 99);
    }

    function test_mintPastMaxSupplyRevertsSoldOut() public {
        vm.store(address(grid), bytes32(MINTED_SLOT), bytes32(uint256(999)));
        uint256 price = grid.priceFor(1000);
        grid.mint{value: price}();
        assertEq(grid.minted(), 1000);
        assertEq(grid.totalSupply(), 1);
        assertEq(grid.currentPrice(), 0);

        vm.expectRevert(GenerativeGrid.SoldOut.selector);
        grid.mint{value: 0}();
        vm.expectRevert(GenerativeGrid.SoldOut.selector);
        grid.mint{value: 1 ether}();
        assertEq(grid.minted(), 1000);
        assertEq(address(grid).balance, price);
    }

    function test_lsp1ReceiverCanRejectAnEvenSeedAndRollTheMintBack() public {
        (uint256 evenRandao, uint256 oddRandao) = _randaoPair(address(grinder), 1);
        uint256 price = grid.currentPrice();
        vm.deal(address(grinder), price * 2);

        vm.prevrandao(bytes32(evenRandao));
        vm.expectRevert("reject even");
        grinder.mint{value: price}();
        assertEq(grid.minted(), 0);
        assertEq(address(grid).balance, 0);
        assertEq(address(grinder).balance, price * 2);
        assertEq(grinder.calls(), 0);

        vm.prevrandao(bytes32(oddRandao));
        grinder.mint{value: price}();
        assertEq(grid.minted(), 1);
        assertEq(grid.seedOf(1) % 2, 1);
        assertEq(grid.tokenOwnerOf(bytes32(uint256(1))), address(grinder));
        assertEq(address(grid).balance, price);
        assertEq(grinder.calls(), 1);
    }

    function test_reentrantMintWithoutASecondPaymentRevertsTheWholeMint() public {
        uint256 price = grid.currentPrice();
        vm.deal(address(reenter), price);
        reenter.arm(false);
        vm.expectRevert(abi.encodeWithSelector(GenerativeGrid.WrongPrice.selector, price, 0));
        reenter.mint{value: price}(price);
        assertEq(grid.minted(), 0);
        assertEq(address(grid).balance, 0);
        assertEq(address(reenter).balance, price);
    }

    function test_reentrantMintPaysForASecondTokenAndCannotDuplicateTheId() public {
        uint256 first = grid.priceFor(1);
        uint256 second = grid.priceFor(2);
        reenter.arm(true);
        reenter.mint{value: first + second}(first);

        assertEq(grid.minted(), 2);
        assertEq(grid.totalSupply(), 2);
        assertEq(grid.tokenOwnerOf(bytes32(uint256(1))), address(reenter));
        assertEq(grid.tokenOwnerOf(bytes32(uint256(2))), address(reenter));
        assertEq(address(grid).balance, first + second);
        assertEq(address(reenter).balance, 0);
        assertTrue(grid.seedOf(1) != grid.seedOf(2));
        // Both mints notify. The second notification does not mint a third token.
        assertEq(reenter.calls(), 2);
    }

    function test_staticcallHookCannotMintASecondToken() public {
        StaticReenteringMinter hook = new StaticReenteringMinter(grid);
        uint256 price = grid.currentPrice();
        vm.deal(address(hook), price);
        hook.mint{value: price}();
        assertEq(grid.minted(), 1);
        assertEq(grid.totalSupply(), 1);
        assertEq(grid.tokenOwnerOf(bytes32(uint256(1))), address(hook));
        assertEq(hook.notifications(), 1);
        assertEq(address(grid).balance, price);
    }

    function test_contractWithoutLsp1CanStillMint() public {
        PlainContractMinter plain = new PlainContractMinter(grid);
        uint256 price = grid.currentPrice();
        vm.deal(address(plain), price);
        plain.mint{value: price}();
        assertEq(grid.minted(), 1);
        assertEq(grid.tokenOwnerOf(bytes32(uint256(1))), address(plain));
        assertEq(grid.seedOf(1), _predict(address(plain), 1));
    }

    function test_twoMintersSameBlockGetSequentialIdsAndDifferentSeeds() public {
        address alice = address(0xA11CE);
        address bob = address(0xB0B);
        vm.deal(alice, BASE * 2);
        vm.deal(bob, BASE * 2);

        uint256 alice1 = _predict(alice, 1);
        uint256 bob1 = _predict(bob, 1);
        assertTrue(alice1 != bob1);

        vm.prank(alice);
        grid.mint{value: BASE}();
        vm.prank(bob);
        grid.mint{value: BASE}();

        assertEq(grid.seedOf(1), alice1);
        assertEq(grid.seedOf(2), _predict(bob, 2));
        assertTrue(grid.seedOf(1) != grid.seedOf(2));
        assertEq(grid.seedOf(1), grid.seedOf(1));
    }

    function test_sameSenderSameBlockDifferentNumbersGetDifferentSeeds() public {
        uint256 first = _predict(address(this), 1);
        uint256 second = _predict(address(this), 2);
        assertTrue(first != second);
        _mintAs(address(this), 2);
        assertEq(grid.seedOf(1), first);
        assertEq(grid.seedOf(2), second);
    }

    function test_prevrandaoChangesTheSeedForTheSameSenderAndNumber() public {
        uint256 a = uint256(keccak256(abi.encode(uint256(11), blockhash(block.number - 1), address(this), uint256(1)))) %
            grid.SEED_RANGE();
        uint256 b = uint256(keccak256(abi.encode(uint256(12), blockhash(block.number - 1), address(this), uint256(1)))) %
            grid.SEED_RANGE();
        assertTrue(a != b);

        vm.prevrandao(bytes32(uint256(11)));
        GenerativeGrid left = _deployReconstruction(address(this), BASE);
        left.mint{value: BASE}();
        assertEq(left.seedOf(1), a);

        vm.prevrandao(bytes32(uint256(12)));
        GenerativeGrid right = _deployReconstruction(address(this), BASE);
        right.mint{value: BASE}();
        assertEq(right.seedOf(1), b);
    }

    function test_mainnetSeedsMatchPrevrandaoParentHashSenderAndNumber() public pure {
        _assertHistorical(0xd6a53ef5cd2eaf9c0b3b2e018a6b335e1a82588c82ca50559ab62d84f6085b5b, 0xb9d3ba92dae1163cfdf05fedfd85fab73372b79539947a07ca2f2dfd4f7ff005, 0x7777c761e451D44F2B7C01D94318996128bc051d, 1, 858479922);
        _assertHistorical(0x68ac7d11b5f6c691db41e64bc930d5027247ad41526ca78f47f50a392d7277e4, 0x5198906784c988a70aac0547ef4d378f329f170b339ea69e52b6325ecf48213f, 0x52224e802F722A3F3f1de8b2157597ae7fEfffD1, 2, 601749066);
        _assertHistorical(0x9541d25b7f8e3198d4c07e40647db67b611986191e1bf550480dfd9adf4345c6, 0xc4055857945ed6ef314939fafa2c6e028c76ebd9114912613438d9a0e60f4900, 0x52224e802F722A3F3f1de8b2157597ae7fEfffD1, 3, 839658880);
        _assertHistorical(0x51bea4d70e1e4822833315e526b6e438e0236f56ef381f056fd8ee49eeaba92f, 0xca4d80fc4b4db3aa20477a22dba3252ba13b6cd893802faf19d71e3e49c00c6e, VAULT, 4, 176084045);
        _assertHistorical(0xa889bde88fe22c0e949f3d7afa89aa27ddd33c04e97d5eb46244f9dec02fe529, 0x2d50d13d9366ac6493f1b89da8f559d0a479f1d38a802a0359f1f4fe2a7b7266, VAULT, 5, 776970099);
        _assertHistorical(0x1d2ccd64eb31a87ea127c3b2e9d615cfe995bf4fdb26479d1c357e86fc2aea8c, 0x9af9da5aac694023741e4428d41f3e3be9462e31f5e2464612f8dfd35d7c3d7d, VAULT, 6, 356576559);
        _assertHistorical(0x7940c166f90bf604e195bf01e97f04d43a028b55e088f1334aecbaaebbe56eb2, 0x40dd4a9646a80364b0e90cf996f6382c3684dfbcb46969f8a63bf675b08d7d49, VAULT, 7, 118881353);
    }

    function test_vaultAddressIsNotOwnerAndCannotWithdrawOrRewrite() public {
        _mintAs(address(this), 1);
        assertTrue(grid.owner() != VAULT);

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(VAULT);
        grid.withdraw(payable(VAULT));

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(VAULT);
        grid.setImageBaseURI("https://example.invalid/");

        bytes32 royalties = grid.LSP18_ROYALTIES_RECIPIENTS();
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(VAULT);
        grid.setData(royalties, hex"00");

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(VAULT);
        grid.setDataForTokenId(bytes32(uint256(1)), _LSP4_METADATA_KEY, hex"01");

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(VAULT);
        grid.transferOwnership(address(0xBEEF));

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(VAULT);
        grid.renounceOwnership();

        assertEq(grid.owner(), address(this));
        assertEq(address(grid).balance, BASE);
        assertEq(grid.imageBaseURI(), "https://minimalnl.github.io/stille-feed/gg/42/");
    }

    function test_unauthorizedWithdrawReverts() public {
        _mintAs(address(this), 1);
        address stranger = address(0xB0B);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(stranger);
        grid.withdraw(payable(stranger));
        assertEq(address(grid).balance, BASE);
    }

    function test_ownerWithdrawPaysAnEoa() public {
        _mintAs(address(this), 1);
        address artist = address(0xA11CE);
        uint256 before = artist.balance;
        grid.withdraw(payable(artist));
        assertEq(artist.balance, before + BASE);
        assertEq(address(grid).balance, 0);
    }

    function test_revertingReceiverDoesNotBrickALaterWithdraw() public {
        _mintAs(address(this), 1);
        vm.expectRevert(GenerativeGrid.WithdrawFailed.selector);
        grid.withdraw(payable(address(sink)));
        assertEq(address(grid).balance, BASE);

        address artist = address(0xA11CE);
        grid.withdraw(payable(artist));
        assertEq(artist.balance, BASE);
        assertEq(address(grid).balance, 0);
    }

    function test_reenteringOwnerCannotWithdrawTwice() public {
        _mintAs(address(this), 1);
        ReenteringOwner greedy = new ReenteringOwner(grid);
        grid.transferOwnership(address(greedy));
        greedy.pull();
        assertEq(greedy.paid(), BASE);
        assertEq(greedy.calls(), 2);
        assertEq(address(grid).balance, 0);
        assertEq(address(greedy).balance, BASE);
    }

    function test_withdrawToAddressZeroBurnsTheBalance() public {
        _mintAs(address(this), 1);
        uint256 zeroBefore = address(0).balance;
        grid.withdraw(payable(address(0)));
        assertEq(address(grid).balance, 0);
        assertEq(address(0).balance, zeroBefore + BASE);
    }

    function test_ownerCanChangeImagesRoyaltiesAndPerTokenMetadata() public {
        _mintAs(address(this), 1);
        string memory computed = grid.tokenMetadataJSON(1);

        grid.setImageBaseURI("ipfs://new/");
        assertEq(grid.imageBaseURI(), "ipfs://new/");
        assertTrue(keccak256(bytes(grid.tokenMetadataJSON(1))) != keccak256(bytes(computed)));

        bytes memory royalty = abi.encodePacked(uint16(28), bytes4(0xffffffff), address(0xBEEF), uint32(200_000));
        grid.setData(grid.LSP18_ROYALTIES_RECIPIENTS(), royalty);
        assertEq(grid.getData(grid.LSP18_ROYALTIES_RECIPIENTS()), royalty);

        bytes memory overrideValue = bytes("stored-override");
        grid.setDataForTokenId(bytes32(uint256(1)), _LSP4_METADATA_KEY, overrideValue);
        assertEq(grid.getDataForTokenId(bytes32(uint256(1)), _LSP4_METADATA_KEY), overrideValue);
        assertTrue(keccak256(bytes(grid.tokenMetadataJSON(1))) != keccak256(overrideValue));
    }

    function test_constructorRoyaltyIsFivePercentAndTransferDoesNotPayIt() public {
        bytes memory expected = abi.encodePacked(uint16(28), bytes4(0xffffffff), address(this), uint32(5000));
        assertEq(grid.getData(grid.LSP18_ROYALTIES_RECIPIENTS()), expected);

        address buyer = address(0xB0B);
        _mintAs(address(this), 1);
        uint256 before = address(grid).balance;
        grid.transfer(address(this), buyer, bytes32(uint256(1)), true, "");
        assertEq(grid.tokenOwnerOf(bytes32(uint256(1))), buyer);
        assertEq(address(grid).balance, before);
        assertEq(buyer.balance, 0);
        assertEq(grid.getData(grid.LSP18_ROYALTIES_RECIPIENTS()), expected);
    }

    function test_constructorRejectsRoyaltyAboveTheBasis() public {
        vm.expectRevert(abi.encodeWithSelector(GenerativeGrid.RoyaltyTooHigh.selector, uint32(100_001)));
        _deployReconstructionWithRoyalty(address(this), BASE, address(this), 100_001);
    }

    function test_compromisedOwnerCannotChangeScriptBasePriceOrSeeds() public {
        _mintAs(address(this), 1);
        uint256 seed = grid.seedOf(1);
        grid.setImageBaseURI("https://example.invalid/");
        grid.withdraw(payable(address(this)));

        assertEq(grid.script(), "function setup(){}");
        assertEq(grid.BASE_PRICE(), BASE);
        assertEq(grid.MAX_SUPPLY(), 1000);
        assertEq(grid.seedOf(1), seed);
        assertEq(grid.SCRIPT_LIBRARY(), "p5.js@1.9.0");

        (bool paused,) = address(grid).call(abi.encodeWithSignature("pause()"));
        (bool setScript,) = address(grid).call(abi.encodeWithSignature("setScript(string)", "hacked"));
        (bool setPrice,) = address(grid).call(abi.encodeWithSignature("setBasePrice(uint256)", uint256(1)));
        assertFalse(paused);
        assertFalse(setScript);
        assertFalse(setPrice);
    }

    function test_renounceOwnershipFreezesWithdrawAndMetadataButNotMint() public {
        _mintAs(address(this), 1);
        grid.renounceOwnership();
        assertEq(grid.owner(), address(0));

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        grid.withdraw(payable(address(this)));
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        grid.setImageBaseURI("ipfs://frozen/");
        assertEq(address(grid).balance, BASE);

        grid.mint{value: grid.currentPrice()}();
        assertEq(grid.minted(), 2);
    }

    function test_transferOwnershipMovesControlAndRejectsZero() public {
        address next = address(0xBEEF);
        vm.expectRevert(bytes("Ownable: new owner is the zero address"));
        grid.transferOwnership(address(0));

        grid.transferOwnership(next);
        assertEq(grid.owner(), next);

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        grid.withdraw(payable(address(this)));

        vm.prank(next);
        grid.setImageBaseURI("ipfs://next/");
        assertEq(grid.imageBaseURI(), "ipfs://next/");
    }

    function test_directEthTransferReverts() public {
        (bool ok,) = address(grid).call{value: 1}("");
        assertFalse(ok);
        assertEq(address(grid).balance, 0);
    }

    function test_burnSelectorIsNotImplemented() public {
        (bool ok,) = address(grid).call(abi.encodeWithSignature("burn(bytes32,bytes)", bytes32(uint256(1)), bytes("")));
        assertFalse(ok);
    }

    function test_unescapedImageBaseCanBreakComputedJson() public {
        _mintAs(address(this), 1);
        grid.setImageBaseURI("https://x/?q=\"");
        string memory json = grid.tokenMetadataJSON(1);
        assertTrue(_contains(json, "https://x/?q=\""));
    }

    function test_reconstructionMetadataMatchesTheDeployedJsonShape() public {
        vm.prevrandao(bytes32(uint256(7)));
        grid.mint{value: BASE}();
        string memory json = grid.tokenMetadataJSON(1);
        assertTrue(_contains(json, '"icon":[]'));
        assertTrue(_contains(json, ".png"));
        assertTrue(_contains(json, "-600.png"));
        assertTrue(_contains(json, "Generative Square #1"));
        assertEq(grid.getDataForTokenId(bytes32(uint256(1)), _LSP4_METADATA_KEY).length > 0, true);
    }

    function test_githubSourceMetadataDiffersFromTheDeployedShape() public {
        vm.prevrandao(bytes32(uint256(7)));
        GitHubGrid github = new GitHubGrid(
            "Generative Square",
            "SQUARE",
            address(this),
            BASE,
            "function setup(){}",
            "https://minimalnl.github.io/stille-feed/gg/42/",
            address(this),
            5000
        );
        github.mint{value: BASE}();
        grid.mint{value: BASE}();

        string memory liveShape = grid.tokenMetadataJSON(1);
        string memory githubShape = github.tokenMetadataJSON(1);
        assertTrue(keccak256(bytes(liveShape)) != keccak256(bytes(githubShape)));
        assertTrue(_contains(liveShape, '"icon":[]'));
        assertTrue(_contains(githubShape, '"icon":[{"width":600'));
        assertTrue(_contains(githubShape, "-600.png"));
        assertFalse(_contains(_imagesOf(githubShape), "-600.png"));
        assertEq(grid.seedOf(1), github.seedOf(1));
    }

    function test_localRuntimeIsNotAnExactMainnetMatch() public {
        bytes memory mainnet = vm.parseBytes(vm.readFile("fixtures/mainnet-runtime.hex"));
        GenerativeGrid priced = _deployReconstruction(address(this), 62_500_000_000_000_000);
        bytes memory local = address(priced).code;
        assertEq(mainnet.length, 15190);
        assertEq(local.length, 15158);
        assertTrue(keccak256(local) != keccak256(mainnet));
    }

    function _jumpAndMintAcross(uint256 already, uint256 boundary, uint256 next) internal {
        vm.store(address(grid), bytes32(MINTED_SLOT), bytes32(already));
        uint256 boundaryPrice = grid.priceFor(boundary);
        uint256 nextPrice = grid.priceFor(next);
        assertTrue(nextPrice == boundaryPrice * 2);
        grid.mint{value: boundaryPrice}();
        assertEq(grid.minted(), boundary);
        grid.mint{value: nextPrice}();
        assertEq(grid.minted(), next);
    }

    function _mintAs(address minter, uint256 count) internal {
        vm.deal(minter, 100 ether);
        for (uint256 i = 0; i < count; i++) {
            uint256 price = grid.currentPrice();
            vm.prank(minter);
            grid.mint{value: price}();
        }
    }

    function _deployReconstruction(address owner_, uint256 base) internal returns (GenerativeGrid) {
        return _deployReconstructionWithRoyalty(owner_, base, owner_, 5000);
    }

    function _deployReconstructionWithRoyalty(address owner_, uint256 base, address royaltyTo, uint32 points)
        internal
        returns (GenerativeGrid)
    {
        return new GenerativeGrid(
            "Generative Square",
            "SQUARE",
            owner_,
            base,
            "function setup(){}",
            "https://minimalnl.github.io/stille-feed/gg/42/",
            royaltyTo,
            points
        );
    }

    function _predict(address sender, uint256 number) internal view returns (uint256) {
        return uint256(keccak256(abi.encode(block.prevrandao, blockhash(block.number - 1), sender, number))) %
            grid.SEED_RANGE();
    }

    function _randaoPair(address sender, uint256 number) internal view returns (uint256 evenRandao, uint256 oddRandao) {
        bytes32 parent = blockhash(block.number - 1);
        for (uint256 i = 1; i < 64; i++) {
            uint256 seed = uint256(keccak256(abi.encode(i, parent, sender, number))) % grid.SEED_RANGE();
            if (evenRandao == 0 && seed % 2 == 0) evenRandao = i;
            if (oddRandao == 0 && seed % 2 == 1) oddRandao = i;
        }
        require(evenRandao != 0 && oddRandao != 0, "no randao pair");
    }

    function _assertHistorical(uint256 prevrandao, bytes32 parent, address sender, uint256 number, uint256 seed)
        internal
        pure
    {
        uint256 calc = uint256(keccak256(abi.encode(prevrandao, parent, sender, number))) % 1_000_000_000;
        assertEq(calc, seed);
    }

    function _imagesOf(string memory json) internal pure returns (string memory) {
        bytes memory raw = bytes(json);
        bytes memory key = bytes(',"images":');
        for (uint256 i = 0; i + key.length < raw.length; i++) {
            bool matchKey = true;
            for (uint256 j = 0; j < key.length; j++) {
                if (raw[i + j] != key[j]) {
                    matchKey = false;
                    break;
                }
            }
            if (matchKey) {
                bytes memory tail = new bytes(raw.length - i);
                for (uint256 k = 0; k < tail.length; k++) tail[k] = raw[i + k];
                return string(tail);
            }
        }
        return json;
    }

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length == 0 || n.length > h.length) return false;
        for (uint256 i = 0; i <= h.length - n.length; i++) {
            bool matchAll = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    matchAll = false;
                    break;
                }
            }
            if (matchAll) return true;
        }
        return false;
    }
}

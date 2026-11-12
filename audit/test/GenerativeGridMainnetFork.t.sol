// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {GenerativeGrid} from "../src/GenerativeGrid.sol";

/// @notice Read-only fork of the already-deployed Generative Square contract.
///         Foundry applies every call inside this process. Nothing is broadcast.
///
///         The public RPC does not serve block 8769224 (`historical state ... is
///         not available`). It does serve a short recent window. FORK_BLOCK is a
///         block inside that window on 12 November 2026. If the node has pruned
///         it, the tests skip instead of pretending the fork ran.
contract GenerativeGridMainnetForkTest is Test {
    address internal constant NFT = 0x33Dd4D3da812e2cc1B3692456470DFDD99659e62;
    address internal constant OWNER = 0x52224e802F722A3F3f1de8b2157597ae7fEfffD1;
    /// @dev Artist vault. Used only as an account that must fail owner calls.
    ///      No test transfers ownership to this address.
    address internal constant VAULT = 0x7070b7Cb8fAe99B6C7DDd0eaBe831DCb6c3047FD;

    /// @dev Pinned after the state window was measured on 12 November 2026.
    ///      Hash 0x796cf66245d1238953eec6b7174cc348aee99c421472d62edae58d4797f9ed22,
    ///      timestamp 1794502068. The RPC refused block 8769224.
    uint256 internal constant FORK_BLOCK = 8769566;
    string internal constant RPC = "https://rpc.mainnet.lukso.network";
    uint256 internal constant MINTED_SLOT = 6;
    uint256 internal constant BASE = 0.0625 ether;

    GenerativeGrid internal grid;
    bool internal forked;

    function setUp() public {
        try this.pinFork() {
            forked = true;
            grid = GenerativeGrid(payable(NFT));
        } catch {
            vm.skip(true);
        }
    }

    /// @dev External so a revert from the RPC is catchable. The cheatcode still
    ///      selects the fork for the calling test.
    function pinFork() external {
        uint256 id = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), id);
    }

    function test_forkPinsTheBlockAndTheLiveRuntime() public {
        assertTrue(forked);
        assertEq(block.number, FORK_BLOCK);
        // blockhash(block.number) is zero inside the EVM. The pin's hash was
        // checked with cast when FORK_BLOCK was chosen; see the report.

        bytes memory live = NFT.code;
        bytes memory fixture = vm.parseBytes(vm.readFile("fixtures/mainnet-runtime.hex"));
        assertEq(live.length, 15190);
        assertEq(keccak256(live), keccak256(fixture));
    }

    function test_forkSupplyPriceAndOwnerMatchTheDeployedState() public {
        assertEq(grid.owner(), OWNER);
        assertTrue(grid.owner() != VAULT);
        assertEq(grid.minted(), 7);
        assertEq(grid.totalSupply(), 7);
        assertEq(uint256(vm.load(NFT, bytes32(MINTED_SLOT))), 7);
        assertEq(address(grid).balance, 0);
        assertEq(grid.BASE_PRICE(), BASE);
        assertEq(grid.currentPrice(), BASE);
        assertEq(grid.priceFor(8), BASE);
        assertEq(grid.MAX_SUPPLY(), 1000);
    }

    function test_forkUnpaidUnderExactAndOverpay() public {
        address buyer = address(0xBEEF);
        uint256 price = grid.currentPrice();
        assertEq(price, BASE);
        vm.deal(buyer, price * 3);

        vm.expectRevert(abi.encodeWithSelector(GenerativeGrid.WrongPrice.selector, price, 0));
        vm.prank(buyer);
        grid.mint{value: 0}();

        vm.expectRevert(abi.encodeWithSelector(GenerativeGrid.WrongPrice.selector, price, price - 1));
        vm.prank(buyer);
        grid.mint{value: price - 1}();

        vm.expectRevert(abi.encodeWithSelector(GenerativeGrid.WrongPrice.selector, price, price + 1));
        vm.prank(buyer);
        grid.mint{value: price + 1}();

        assertEq(grid.minted(), 7);
        assertEq(address(grid).balance, 0);
        assertEq(buyer.balance, price * 3);

        bytes32 codehash = NFT.codehash;
        vm.prank(buyer);
        grid.mint{value: price}();

        assertEq(grid.minted(), 8);
        assertEq(grid.totalSupply(), 8);
        assertEq(grid.tokenOwnerOf(bytes32(uint256(8))), buyer);
        assertEq(address(grid).balance, price);
        assertEq(buyer.balance, price * 2);
        assertEq(NFT.codehash, codehash);
        assertEq(NFT.code.length, 15190);
    }

    function test_forkSoldOutUsesTheLiveMintedSlot() public {
        assertEq(uint256(vm.load(NFT, bytes32(MINTED_SLOT))), grid.minted());
        vm.store(NFT, bytes32(MINTED_SLOT), bytes32(uint256(1000)));
        assertEq(grid.minted(), 1000);
        assertEq(grid.currentPrice(), 0);

        address buyer = address(0xBEEF);
        vm.deal(buyer, 1 ether);
        vm.expectRevert(GenerativeGrid.SoldOut.selector);
        vm.prank(buyer);
        grid.mint{value: 1 ether}();
        assertEq(grid.minted(), 1000);
        assertEq(address(grid).balance, 0);

        vm.store(NFT, bytes32(MINTED_SLOT), bytes32(uint256(999)));
        uint256 last = grid.priceFor(1000);
        assertEq(last, 32 ether);
        vm.deal(buyer, last);
        vm.prank(buyer);
        grid.mint{value: last}();
        assertEq(grid.minted(), 1000);
        assertEq(grid.tokenOwnerOf(bytes32(uint256(1000))), buyer);
    }

    function test_forkVaultCannotWithdrawOrWriteAndOwnerCan() public {
        vm.deal(NFT, 1 ether);

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(VAULT);
        grid.withdraw(payable(VAULT));

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(VAULT);
        grid.setImageBaseURI("https://example.invalid/nope/");

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(VAULT);
        grid.transferOwnership(address(0xB0B));

        uint256 ownerBefore = OWNER.balance;
        vm.prank(OWNER);
        grid.withdraw(payable(OWNER));
        assertEq(address(grid).balance, 0);
        assertEq(OWNER.balance, ownerBefore + 1 ether);
        assertEq(grid.owner(), OWNER);

        vm.prank(OWNER);
        grid.setImageBaseURI("https://example.invalid/fork-only/");
        assertEq(grid.imageBaseURI(), "https://example.invalid/fork-only/");

        // Moves NFT ownership on this fork only, and not to the vault.
        vm.prank(OWNER);
        grid.transferOwnership(address(0xB0B));
        assertEq(grid.owner(), address(0xB0B));
        assertTrue(grid.owner() != VAULT);
    }
}

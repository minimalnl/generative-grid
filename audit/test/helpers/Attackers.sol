// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {GenerativeGrid} from "../../src/GenerativeGrid.sol";

/// @dev Local fixtures. They target whatever GenerativeGrid the test deploys.
///      Nothing here knows a mainnet RPC or broadcasts a transaction.

contract RejectingReceiver {
    GenerativeGrid public immutable grid;
    uint256 public calls;

    constructor(GenerativeGrid grid_) {
        grid = grid_;
    }

    function mint() external payable {
        grid.mint{value: msg.value}();
    }

    function universalReceiver(bytes32, bytes calldata) external returns (bytes memory) {
        calls += 1;
        if (grid.seedOf(grid.minted()) % 2 == 0) revert("reject even");
        return "";
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x6bb56a14 || interfaceId == 0x01ffc9a7;
    }
}

contract ReenteringMinter {
    GenerativeGrid public immutable grid;
    bool public reenter;
    bool public payAgain;
    uint256 public calls;

    constructor(GenerativeGrid grid_) {
        grid = grid_;
    }

    function arm(bool payAgain_) external {
        reenter = true;
        payAgain = payAgain_;
    }

    function mint(uint256 firstPrice) external payable {
        grid.mint{value: firstPrice}();
    }

    function universalReceiver(bytes32, bytes calldata) external returns (bytes memory) {
        calls += 1;
        if (!reenter) return "";
        reenter = false;
        if (payAgain) {
            uint256 price = grid.currentPrice();
            grid.mint{value: price}();
        } else {
            grid.mint{value: 0}();
        }
        return "";
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x6bb56a14 || interfaceId == 0x01ffc9a7;
    }

    receive() external payable {}
}

/// @notice supportsInterface runs under staticcall on the mint path.
///         A second mint attempted from that hook cannot change state.
contract StaticReenteringMinter {
    GenerativeGrid public immutable grid;
    uint256 public notifications;

    constructor(GenerativeGrid grid_) {
        grid = grid_;
    }

    function mint() external payable {
        grid.mint{value: msg.value}();
    }

    function supportsInterface(bytes4 interfaceId) external returns (bool) {
        try grid.mint{value: 0}() {} catch {}
        return interfaceId == 0x6bb56a14 || interfaceId == 0x01ffc9a7;
    }

    function universalReceiver(bytes32, bytes calldata) external returns (bytes memory) {
        notifications += 1;
        return "";
    }
}

contract PlainContractMinter {
    GenerativeGrid public immutable grid;

    constructor(GenerativeGrid grid_) {
        grid = grid_;
    }

    function mint() external payable {
        grid.mint{value: msg.value}();
    }
}

/// @notice Thrown after a successful local mint so the whole transaction rolls back.
///         The seed is in the revert data, which is the only place it survives the rollback.
error SawSeed(uint256 seed);

/// @notice Not an LSP1 receiver: no supportsInterface, no universalReceiver.
///         It mints, reads the seed the mint just wrote, then reverts.
contract SeedPeekingMinter {
    GenerativeGrid public immutable grid;

    constructor(GenerativeGrid grid_) {
        grid = grid_;
    }

    function mint() external payable {
        grid.mint{value: msg.value}();
        revert SawSeed(grid.seedOf(grid.minted()));
    }
}

contract RevertingSink {
    receive() external payable {
        revert("sink");
    }
}

contract ReenteringOwner {
    GenerativeGrid public immutable grid;
    uint256 public calls;
    uint256 public paid;

    constructor(GenerativeGrid grid_) {
        grid = grid_;
    }

    function pull() external {
        grid.withdraw(payable(address(this)));
    }

    receive() external payable {
        calls += 1;
        paid += msg.value;
        if (msg.value > 0) {
            grid.withdraw(payable(address(this)));
        }
    }
}

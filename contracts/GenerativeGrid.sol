// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title GenerativeGrid
 * @notice Generative Square on-chain NFT contract
 * @dev Live deployment: 0x33Dd4D3da812e2cc1B3692456470DFDD99659e62
 * 
 * This contract serves as the source-of-truth for metadata structure.
 * The live mainnet contract is already deployed and immutable.
 * 
 * IMPORTANT: Never transfer ownership to 0x7070b7Cb8fAe99B6C7DDd0eaBe831DCb6c3047FD
 */
contract GenerativeGrid {
    string private constant BASE_URI = "https://generative-square.example.com/art/";
    
    /**
     * @notice Returns the metadata JSON for a given token
     * @dev Updated structure for Universal Everything compatibility:
     *      - icon: Array of image objects (600x600 thumbnail)
     *      - images: Nested array with only the main artwork (2400x2400)
     * @param tokenId The token ID to get metadata for
     * @return JSON string containing token metadata
     */
    function tokenMetadataJSON(uint256 tokenId) public pure returns (string memory) {
        return string(abi.encodePacked(
            '{',
                '"name":"Generative Square #', _toString(tokenId), '",',
                '"description":"Generative Square is an on-chain generative art collection.",',
                '"icon":[',
                    '{',
                        '"width":600,',
                        '"height":600,',
                        '"url":"', BASE_URI, _toString(tokenId), '-600.png"',
                    '}',
                '],',
                '"images":[[',
                    '{',
                        '"width":2400,',
                        '"height":2400,',
                        '"url":"', BASE_URI, _toString(tokenId), '.png"',
                    '}',
                ']],',
                '"links":[],',
                '"assets":[],',
                '"attributes":[',
                    '{',
                        '"key":"Seed",',
                        '"value":"', _toString(tokenId), '",',
                        '"type":"string"',
                    '}',
                ']',
            '}'
        ));
    }
    
    /**
     * @notice Returns the VerifiableURI encoded metadata value
     * @dev Wraps the JSON in the VerifiableURI structure
     * @param tokenId The token ID
     * @return Encoded metadata value
     */
    function _tokenMetadataValue(uint256 tokenId) internal pure returns (bytes memory) {
        bytes memory jsonData = bytes(tokenMetadataJSON(tokenId));
        return abi.encodePacked(
            hex"00006f357c6a0020",  // VerifiableURI header
            uint256(keccak256(jsonData)),  // hash
            "data:application/json;utf8,",
            jsonData
        );
    }
    
    /**
     * @dev Converts uint256 to string
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}

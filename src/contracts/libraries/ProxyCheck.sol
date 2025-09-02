// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;


/**
 * Library for interacting and validating proxy contracts.
 */
library ProxyCheck {

    /**
     * Gets the implementation of a proxy contract by decoding the EIP-1167 minimal proxy pattern.
     *
     * @param _proxy The address of the proxy contract
     *
     * @return implementation_ The address of the implementation contract
     */
    function getImplementation(address _proxy) internal view returns (address implementation_) {
        // Decode the EIP-1167 minimal proxy pattern
        bytes memory code = new bytes(45);
        assembly {
            extcodecopy(_proxy, add(code, 32), 0, 45)
        }

        // EIP-1167 minimal proxy: 0x363d3d373d3d3d363d73<20-byte impl>5af43d82803e903d91602b57fd5bf3
        // The implementation address is at offset 10 (after 0x363d3d373d3d3d363d73)
        if (
            code.length == 45 &&
            uint8(code[0]) == 0x36 &&
            uint8(code[1]) == 0x3d &&
            uint8(code[2]) == 0x3d &&
            uint8(code[3]) == 0x37 &&
            uint8(code[4]) == 0x3d &&
            uint8(code[5]) == 0x3d &&
            uint8(code[6]) == 0x3d &&
            uint8(code[7]) == 0x36 &&
            uint8(code[8]) == 0x3d &&
            uint8(code[9]) == 0x73
        ) {
            assembly {
                implementation_ := mload(add(code, 30)) // 10+20=30
            }
        }
    }
}
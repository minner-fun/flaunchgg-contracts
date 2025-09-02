// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {Pausable} from '@openzeppelin/contracts/utils/Pausable.sol';

import {MockERC20} from '@uniswap/v4-core/lib/forge-std/src/mocks/MockERC20.sol';


/**
 * Deploys MockERC20 contracts that can be used by the Token Importer
 */
contract MockERC20Factory is Ownable, Pausable {

    /// Event emitted when a new token is deployed
    event TokenDeployed(address indexed token, string name, string symbol, address indexed deployer);

    /// Mapping to track deployed tokens
    mapping (address _token => bool _exists) public deployedTokens;

    constructor() Ownable(msg.sender) {
        // ..
    }

    /**
     * Deploys a new MockERC20 token.
     * 
     * @param name The name of the token
     * @param symbol The symbol of the token
     *
     * @return token_ The address of the deployed token
     */
    function deployToken(string memory name, string memory symbol) public whenNotPaused returns (address token_) {
        // Deploy the new token
        MockERC20 newToken = new MockERC20();
        
        // Capture the address of the deployed token
        token_ = address(newToken);
        
        // Initialize the token with 18 decimals
        newToken.initialize(name, symbol, 18);
        
        // Track the deployed token
        deployedTokens[token_] = true;
        
        // Emit event
        emit TokenDeployed(token_, name, symbol, msg.sender);
    }

    /**
     * Pause the factory
     */
    function pause(bool _paused) public onlyOwner {
        if (_paused) {
            _pause();
        } else {
            _unpause();
        }
    }
}

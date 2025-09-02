// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IImportVerifier} from '@flaunch-interfaces/IImportVerifier.sol';


interface IDopplerAirlock {

    struct AssetData {
        address numeraire;
        address timelock;
        address governance;
        address liquidityMigrator;
        address poolInitializer;
        address pool;
        address migrationPool;
        uint256 numTokensToSell;
        uint256 totalSupply;
        address integrator;
    }

    function getAssetData(address _asset) external view returns (AssetData memory);

}


/**
 * Confirms that a memecoin has been deployed on Doppler.
 */
contract DopplerVerifier is IImportVerifier {
    
    /// The Clanker contract
    IDopplerAirlock public immutable doppler;

    /**
     * Registers the Doppler Airlock contract.
     *
     * @param _doppler The address of the Doppler Airlock contract
     */
    constructor (address _doppler) {
        doppler = IDopplerAirlock(_doppler);
    }

    /**
     * Checks if a token exists on Doppler.
     *
     * @param _token The address of the token to verify
     * @param _sender The address of the sender
     *
     * @return bool True if the token exists on Doppler, false otherwise
     */
    function isValid(address _token, address _sender) public view returns (bool) {
        // Confirm that the token is deployed on Doppler
        IDopplerAirlock.AssetData memory asset = doppler.getAssetData(_token);
        if (asset.poolInitializer == address(0)) {
            return false;
        }

        // Confirm that the sender is registered integrator of the token
        return asset.integrator == _sender;
    }

}